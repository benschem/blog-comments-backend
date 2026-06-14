#!/usr/bin/env bash
set -euo pipefail

# Restore the comments SQLite database from an R2 backup.
#
# Run this from your LAPTOP, which holds R2 *read* credentials. The server only ever has a
# write-only token, so it can't list or download backups itself - restore is a deliberate,
# hands-on act, not something the app can do on its own.
#
# Usage: ./restore-backup.sh <vps-ip> <ssh-key-path> [object-key]
#   object-key  optional; the backup to restore (e.g. comments-20260614T033000Z.sqlite3.gz).
#               Defaults to the most recent backup in the bucket.
#
# Host-specific settings (SSH_USER / APP_DIR / SERVICE / PORT) default to the values below.
# Override any of them via the environment, or via an optional (gitignored) scripts/deploy.env,
# when restoring to a different box. Set FORCE=1 to skip the confirmation.

if [ "$#" -lt 2 ]; then
  echo "Usage: ./restore-backup.sh <vps-ip> <ssh-key-path> [object-key]"
  exit 1
fi

IP="$1"
SSH_KEY="$2"
OBJECT_KEY="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Host-specific settings. Precedence: explicit environment > scripts/deploy.env > built-in
# defaults. Capture any env overrides first so sourcing deploy.env can't clobber them.
_ENV_SSH_USER="${SSH_USER:-}"; _ENV_APP_DIR="${APP_DIR:-}"
_ENV_SERVICE="${SERVICE:-}"; _ENV_PORT="${PORT:-}"
if [ -f "$SCRIPT_DIR/deploy.env" ]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/deploy.env"
fi
SSH_USER="${_ENV_SSH_USER:-${SSH_USER:-comments}}"
APP_DIR="${_ENV_APP_DIR:-${APP_DIR:-/home/comments/blog-comments-backend}}"
SERVICE="${_ENV_SERVICE:-${SERVICE:-comments}}"  # docker-compose service name
PORT="${_ENV_PORT:-${PORT:-9292}}"               # loopback port the app + /up listen on

DB_REMOTE="$APP_DIR/db/comments_prod.sqlite3"    # bind-mounted SQLite file on the host
COMPOSE_REMOTE="docker compose -f $APP_DIR/docker-compose.yml"
R2_BUCKET="s3://blog-comments-backups"
R2_CREDS="${R2_CREDS:-$HOME/.r2-credentials}"    # your laptop's R2 read credentials

# A unique remote upload path and one timestamp, both decided here so we can name the
# pre-restore safety copy deterministically and print an exact rollback command later.
TS="$(date -u +%Y%m%dT%H%M%SZ)"
REMOTE_TMP="/tmp/comments-restore.$$.sqlite3"

# SSH/SCP as arrays so paths with spaces survive and there's no word-splitting guesswork.
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -i "$SSH_KEY")
SSH=(ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP")
SCP=(scp "${SSH_OPTS[@]}")

# --- Local preflight ---------------------------------------------------------------------

for tool in aws gunzip ssh scp; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Error: required tool '$tool' not found in PATH"; exit 1; }
done
HAVE_SQLITE=1
command -v sqlite3 >/dev/null 2>&1 || HAVE_SQLITE=0

if [ ! -f "$SSH_KEY" ]; then
  echo "Error: ssh key not found at $SSH_KEY"
  exit 1
fi
KEY_PERMS="$(stat -f '%Lp' "$SSH_KEY" 2>/dev/null || stat -c '%a' "$SSH_KEY" 2>/dev/null || echo '')"
case "$KEY_PERMS" in
  600|400|'') ;;
  *) echo "Warning: $SSH_KEY perms are $KEY_PERMS (expected 600); ssh may refuse it." ;;
esac

if [ ! -f "$R2_CREDS" ]; then
  echo "Error: R2 credentials not found at $R2_CREDS"
  echo "Create it (a read-capable token) with:"
  echo "  export AWS_ACCESS_KEY_ID=..."
  echo "  export AWS_SECRET_ACCESS_KEY=..."
  echo "  export AWS_ENDPOINT_URL=https://<account-id>.r2.cloudflarestorage.com"
  echo "  export AWS_DEFAULT_REGION=auto"
  exit 1
fi

# shellcheck source=/dev/null
source "$R2_CREDS"
# R2 has no real regions, but the AWS CLI insists one be set; 'auto' is the convention.
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-auto}"
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_ENDPOINT_URL
: "${AWS_ENDPOINT_URL:?AWS_ENDPOINT_URL not set in $R2_CREDS}"

# --- Remote preflight (before downloading anything) --------------------------------------

if ! "${SSH[@]}" "test -f $APP_DIR/docker-compose.yml && test -d $APP_DIR/db && test -w $APP_DIR/db"; then
  echo "Error: remote preflight failed on $IP."
  echo "  Expected $APP_DIR/docker-compose.yml and a writable $APP_DIR/db (as user '$SSH_USER')."
  echo "  Check APP_DIR/SSH_USER (see scripts/deploy.env) or that the box is provisioned."
  exit 1
fi

# --- Pick + show the backup --------------------------------------------------------------

LISTING="$(aws s3 ls "$R2_BUCKET/" --endpoint-url "$AWS_ENDPOINT_URL")"

# Default to the most recent backup. Sort the keys themselves (ISO-8601 timestamps sort
# chronologically) and ignore anything that isn't one of our snapshots.
if [ -z "$OBJECT_KEY" ]; then
  OBJECT_KEY="$(printf '%s\n' "$LISTING" \
    | awk '{print $4}' \
    | grep -E '^comments-[0-9]{8}T[0-9]{6}Z\.sqlite3\.gz$' \
    | sort | tail -1)"
fi
if [ -z "$OBJECT_KEY" ]; then
  echo "Error: no backups found in $R2_BUCKET"
  exit 1
fi

# Confirm the chosen object exists and surface its size + timestamp so the operator can
# sanity-check they're restoring what they think.
META_LINE="$(printf '%s\n' "$LISTING" | awk -v k="$OBJECT_KEY" '$4==k {print; exit}')"
if [ -z "$META_LINE" ]; then
  echo "Error: object '$OBJECT_KEY' not found in $R2_BUCKET"
  exit 1
fi
echo "Restoring: $OBJECT_KEY"
echo "  $META_LINE"

# --- Download + gunzip + verify ----------------------------------------------------------

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
aws s3 cp "$R2_BUCKET/$OBJECT_KEY" "$WORK/backup.sqlite3.gz" --endpoint-url "$AWS_ENDPOINT_URL" --no-progress
gunzip "$WORK/backup.sqlite3.gz" # -> $WORK/backup.sqlite3

# Verify the snapshot opens cleanly *before* we touch the live box. A truncated download is
# already caught by gunzip; this also catches valid-gzip-but-corrupt-SQLite.
if [ "$HAVE_SQLITE" = "1" ]; then
  INTEGRITY="$(sqlite3 "$WORK/backup.sqlite3" 'PRAGMA integrity_check' 2>/dev/null || echo 'FAILED')"
  if [ "$INTEGRITY" != "ok" ]; then
    echo "Error: downloaded backup failed PRAGMA integrity_check (got: $INTEGRITY)"
    exit 1
  fi
  echo "Integrity check: ok"
else
  MAGIC="$(head -c 16 "$WORK/backup.sqlite3" | tr -d '\0')"
  if [ "$MAGIC" != "SQLite format 3" ]; then
    echo "Error: downloaded file is not a SQLite database"
    exit 1
  fi
  echo "Warning: sqlite3 not installed; verified the SQLite header only (skipped full integrity_check)."
fi

# --- Confirm (this is the destructive point) ---------------------------------------------

if [ "${FORCE:-}" = "1" ]; then
  echo "FORCE=1 set; skipping confirmation."
else
  read -r -p "This OVERWRITES the live database on $IP. Type 'yes' to continue: " reply || reply=""
  [ "$reply" = "yes" ] || { echo "Aborted."; exit 1; }
fi

# --- Ship it up, then swap it in while the app is stopped ---------------------------------

"${SCP[@]}" "$WORK/backup.sqlite3" "$SSH_USER@$IP:$REMOTE_TMP"

# Quoted heredoc: nothing expands locally. The box-side values it needs are passed as
# positional args, so `date`/`stat`/`find` all run remotely as intended.
"${SSH[@]}" bash -s -- "$APP_DIR" "$SERVICE" "$REMOTE_TMP" "$TS" <<'REMOTE'
set -euo pipefail
APP_DIR="$1"; SERVICE="$2"; REMOTE_TMP="$3"; TS="$4"
COMPOSE="docker compose -f $APP_DIR/docker-compose.yml"
DB="$APP_DIR/db/comments_prod.sqlite3"

# Always clean up the uploaded temp, however this block exits.
trap 'rm -f "$REMOTE_TMP"' EXIT
[ -f "$REMOTE_TMP" ] || { echo "remote: uploaded file missing at $REMOTE_TMP" >&2; exit 1; }

$COMPOSE stop "$SERVICE"

# Safety copy of the current live DB so a bad restore is recoverable. Capture its
# owner/mode too - the container runs as a non-root user and the restored file must end
# up owned the same way or the app can't open it.
OWNER=""; MODE=""
if [ -f "$DB" ]; then
  cp -p "$DB" "$DB.pre-restore-$TS"
  [ -f "$DB-wal" ] && cp -p "$DB-wal" "$DB.pre-restore-$TS-wal" || true
  [ -f "$DB-shm" ] && cp -p "$DB-shm" "$DB.pre-restore-$TS-shm" || true
  OWNER="$(stat -c '%u:%g' "$DB")"
  MODE="$(stat -c '%a' "$DB")"
  echo "remote: saved pre-restore copy -> $DB.pre-restore-$TS"
  # Keep the disk on this shared box tidy - drop safety copies older than a week.
  find "$APP_DIR/db" -maxdepth 1 -type f -name 'comments_prod.sqlite3.pre-restore-*' -mtime +7 -delete 2>/dev/null || true
fi

mv "$REMOTE_TMP" "$DB"

if [ -n "$OWNER" ]; then
  chown "$OWNER" "$DB" 2>/dev/null || echo "remote: warning - could not chown $DB to $OWNER (restore continues)" >&2
  chmod "$MODE" "$DB" 2>/dev/null || true
fi

# Drop any stale WAL/SHM so SQLite can't replay an old write-ahead log over the restore.
rm -f "$DB-wal" "$DB-shm"

$COMPOSE up -d "$SERVICE"
REMOTE

# --- Wait for the app to come back healthy (/up runs SELECT 1 against the restored DB) ----

echo -n "Waiting for the app "
for _ in $(seq 1 30); do
  if "${SSH[@]}" "curl -fsS http://127.0.0.1:$PORT/up" >/dev/null 2>&1; then
    echo " healthy."
    echo "Restore complete. A pre-restore copy is kept at $DB_REMOTE.pre-restore-$TS"
    echo "Run 'rake comments:pending' on the box to eyeball the data."
    exit 0
  fi
  echo -n "."
  sleep 2
done

# Health never came back - surface logs and an exact, paste-ready rollback command.
echo
echo "Warning: /up did not come back within ~60s. Recent logs:"
"${SSH[@]}" "$COMPOSE_REMOTE logs --tail=50 $SERVICE" 2>/dev/null || true
echo
echo "Roll back to the pre-restore copy with:"
echo "  ${SSH[*]} '$COMPOSE_REMOTE stop $SERVICE && mv $DB_REMOTE.pre-restore-$TS $DB_REMOTE && rm -f $DB_REMOTE-wal $DB_REMOTE-shm && $COMPOSE_REMOTE up -d $SERVICE'"
exit 1
