# blog-comments-backend

A small self-hosted comments backend for a separate statically generated frontend.

Unlike most of the existing options, it lets anyone comment without logging in.

Built with Sinatra, ActiveRecord and SQLite to run containerised on a VPS.

## How it works

With a static frontend on free hosting, comments (inherently dynamic) are awkward.

This backend stores the submitted comments and the frontend fetches them once at
build time. The frontend rebuild is triggered by this backend when a comment is
approved.

1. A visitor submits a comment via a no-JS HTML form on the frontend that `POST`s
   to `/comments`. It is stored on server in SQLite DB as `pending` and is not public.
2. The backend emails the moderator (via [Resend](https://resend.com)) with the
   comment and a link to a moderation page containing unguessable approve/reject links.
3. Moderator clicks approve. The comment is marked as `approved` and fires the
   frontend's build hook (Netlify in this setup; any host with a deploy hook works).
4. The frontend rebuilds, fetching approved comments at build time
   (`GET /comments?post_slug=…`) and baking them into static HTML.

No comment is public until the moderator approves it, so no need for a captcha,
user accounts, or commenter email confirmation.

Kept simple with no admin dashboard. Email and CLI is the only moderation UI.

### Why these choices (short version)

- A self-hosted backend rather than giscus or comments-in-git. Those force
  commenters to have a GitHub account; the whole point is to let anyone comment.
- Moderation is approve-first. Email confirmation is near-zero spam protection
  (bots have mailboxes), so inverting it — nothing publishes until the moderator
  acts — makes spam impossible to publish.
- The moderator gets notified; strangers don't get verified. Notifying is one
  outbound request. Verifying strangers is the whole expensive apparatus
  (deliverability, PII, confirm/expire state), so no commenter email is stored at all.
- Comments bake in at build time and a rebuild fires on approve. That keeps every
  page a zero-JS static document (Lighthouse-100, crawlable) and sidesteps
  adblockers, since reads happen server-side at build time.

## Data model

A single `comments` table. The columns:

- `post_slug` (string, not null): keys comments to a post (slugs must stay stable).
- `author_name` (string, not null): the only required public field.
- `author_website` (string, optional): rendered as `rel="nofollow ugc"`.
- `author_role` (string, optional): short job-title/role.
- `body` (text, not null): plain text, escaped on render.
- `status` (string, not null, default `pending`): enum, see below.
- `moderation_token` (string, not null, unique): unguessable capability gating the approve/reject links.
- `ip_address` (string): spam triage, never displayed.
- `user_agent` (text): spam triage, never displayed.
- `created_at` / `updated_at` (datetime): timestamps.

Notes:

- `status` is a string enum, not a boolean: `pending / approved / spam / rejected`, so
  "rejected on purpose" is distinguishable from "not looked at yet".
- No email or PII stored. Nothing to disclose, nothing to delete on request.
- `public_attributes` is an explicit allow-list (`author_name`, `author_website`,
  `author_role`, `body`, `created_at`). The token, IP, user-agent and status are
  never served.
- Indexes: `[post_slug, status]` (covers the public read query) and a unique index
  on `moderation_token`.

## API

- `POST /comments`: submit a comment. Stored `pending`, then a Resend
  notification is queued to a background worker (`sucker_punch`) so the response
  isn't blocked on the email round-trip. Honeypot field `homepage` returns a
  silent success with no row. Throttled to 5/60s per IP. Bodies over 64 KB are
  rejected with `413` before parsing.
- `GET /comments?post_slug=…`: approved comments for a post, oldest first,
  `public_attributes` only (JSON).
- `GET /moderate/:token`: prefetch-safe confirm page with approve / reject /
  mark-spam forms. Zero side effects.
- `POST /moderate/:token/approve`: `approve!` the comment, then fire the build
  hook.
- `POST /moderate/:token/reject`: `reject!` the comment. No hook.
- `POST /moderate/:token/mark_spam`: `mark_spam!` the comment. No hook.
- `GET /up`: health check. Runs `SELECT 1` against the DB and returns
  `{"status":"ok"}` (200) or `{"status":"error"}` (503). Used by the Docker
  healthcheck and uptime monitoring.

Moderation mutations happen on POST, not GET, because mail clients prefetch GET
links.

## Command-line moderation

The email links are the primary moderation UI, but the same actions are available
from the terminal as a fallback, handy over SSH on the VPS or if a notification
never arrives. The notification is sent from an in-memory background queue, so a
crash or restart mid-send can drop it silently with no retry; `comments:pending`
is the durable backstop that makes sure such a comment is never lost. All run via
`bundle exec rake`:

- `comments:pending`: list the comments awaiting moderation, each with its id,
  local (AEST) timestamp, post, author and a body excerpt.
- `comments:approve[<id>]`: approve a comment by id, then fire the build hook.
  The approval persists even if the hook fails (it's reported, not fatal).
- `comments:reject[<id>]`: reject a comment by id. No hook.
- `comments:mark_spam[<id>]`: mark a comment as spam by id. No hook.

```sh
bundle exec rake comments:pending
bundle exec rake 'comments:approve[42]' # quote the brackets so the shell doesn't glob them
bundle exec rake 'comments:reject[42]'
bundle exec rake 'comments:mark_spam[42]'
```

Run `comments:pending` first to get the ids; the others print the result and
abort with a clear message on an unknown or missing id.

## Project layout

```
.
├── app.rb                   # bootstrap: requires + the Rack::Builder middleware stack (RackApp)
├── config.ru                # Puma entry point: boots config, starts the scheduler, runs RackApp
├── Rakefile                 # db:* tasks + comments:* CLI moderation tasks
├── bin/
│   ├── dev                  # local boot (rackup -q, single access log)
│   └── docker-entrypoint.sh # db:create + db:migrate, then exec puma
├── config/
│   ├── database.yml         # per-env SQLite (WAL), chosen by RACK_ENV
│   ├── app_config.rb        # AppConfig: immutable ENV value object, fail-fast on boot
│   ├── backup_config.rb     # BackupConfig: R2 credentials, validated lazily (not at boot)
│   ├── app_logger.rb        # AppLogger: one stdout logger for the non-Sinatra objects
│   ├── puma.rb              # Puma config
│   ├── rack_attack.rb       # per-IP throttle config
│   └── scheduler.rb         # rufus-scheduler cron: stale-pending alert, spam digest, R2 backup
├── app/
│   ├── models/comment.rb    # the Comment model
│   ├── controllers/         # base, health, comments, moderation (Sinatra::Base subclasses)
│   ├── middleware/          # RejectOversizeRequests (413 guard)
│   └── jobs/                # NotifyModeratorJob (sucker_punch)
├── mailer/
│   ├── app_mailer.rb        # AppMailer: Resend transport, 10s timeout
│   ├── mail_helpers.rb      # escape_html
│   └── mail/                # ModerationEmail, PendingAlertEmail, SpamDigestEmail, BackupFailureEmail
├── lib/                     # BuildHook, Sigv4Signer, BackupUploader, SqliteBackup
├── scripts/restore-backup.sh # laptop-run restore of the database from an R2 backup
├── views/moderate.erb       # the moderation confirm page (noindex)
├── db/                      # migrate/ + schema.rb (databases gitignored)
└── spec/                    # RSpec + rack-test + factory_bot + database_cleaner
```

`app.rb` is the single setup point. It loads config, models, mailer, jobs and
controllers, then assembles them into a `Rack::Builder` stack (`RackApp`). Each
controller is a `Sinatra::Base` subclass extending `BaseController` (shared DB
connection and protection settings); the stack mounts them in order, with the
health check first so its probe never reaches the access log. `config.ru` requires
`app.rb`, memoizes `AppConfig` (crashing on any missing ENV), starts the scheduler
in production, and runs `RackApp` under Puma. Rake tasks load `app.rb` directly, so
they get the models and lib without the web stack.

## Getting started

Requires Ruby 3.4.5 (pinned in `.ruby-version`).

```sh
bundle install

bundle exec rake db:create                   # create dev + test databases
bundle exec rake db:migrate                  # migrate dev
RACK_ENV=test bundle exec rake db:migrate    # migrate the test DB too

bundle exec rake db:seed                     # optional: sample comments for local dev

cp .env.example .env                         # then fill in the values below

bin/dev                                      # boot locally on :9292 (single access log)
```

### Tests & linting

```sh
bundle exec rspec     # run the suite (coverage via simplecov → coverage/)
bundle exec rubocop   # lint
```

### Environment variables

Copy `.env.example` to `.env` and set:

- `RACK_ENV`: `development` / `test` / `production`.
- `APP_BASE_URL`: base URL so moderation links in emails resolve.
- `RESEND_API_KEY`: Resend API key for moderation notifications.
- `RESEND_FROM_EMAIL`: sender address, e.g. `comments@benschem.dev`.
- `MODERATION_NOTIFY_EMAIL`: inbox that receives new-comment notifications and the
  stale-pending digest.
- `BUILD_HOOK_URL`: the frontend host's build/deploy hook, fired on approve. Any
  host works (Netlify is the reference); it's just a URL the backend POSTs to.

`AppConfig` reads these once at boot and crashes immediately if any required one
is blank, so a half-configured deploy fails fast instead of running broken.

The database backup needs three more, **production only**: `R2_ACCESS_KEY_ID`,
`R2_SECRET_ACCESS_KEY`, `R2_ENDPOINT`. These are read by `BackupConfig` lazily (only
when a backup runs), not by `AppConfig` at boot, so leaving them blank never blocks
local dev/test, and a missing one fails the backup rather than the web app. See
*Backups & restore*.

## Deployment

Ships as a self-contained Docker stack (`Dockerfile` + `docker-compose.yml`). It
binds `127.0.0.1:9292` and expects a reverse proxy on the host to terminate TLS and
forward to it; nothing else needs to reach it.

```sh
git clone <repo-url> && cd blog-comments-backend
# create .env.production with the variables above (no blanks; a missing one crashes boot)
mkdir -p db                       # bind-mount target for the persistent SQLite DB
docker compose up -d --build      # entrypoint runs db:create db:migrate, then Puma
curl -sS http://127.0.0.1:9292/up # {"status":"ok"}
```

The container preloads jemalloc, sets `TZ` (Dockerfile, defaults to
`Australia/Sydney`) so log lines are local time, caps memory at 256M, and rotates
its logs (3 x 10 MB). Compose runs the `/up` health check on an interval. SQLite
runs in WAL mode (`config/database.yml`), so the single writer and readers don't
block each other.

You still need a reverse proxy out front for TLS and a public hostname.

## Stranded-comment safety net

There is no dashboard, so a comment can strand in `pending` forever two ways:
Resend fails to deliver the notification, or the notify job is dropped before it
runs. `sucker_punch` is an in-memory queue, so a job lost to a Puma restart sends
no email and logs nothing. Logging can't catch that; only a periodic check of the
DB can.

In production, `config.ru` starts an in-process scheduler (`rufus-scheduler`, see
`config/scheduler.rb`) on a wall-clock cron, twice daily at 8am and 8pm Sydney
time. Each run finds comments still `pending` after 24h and emails the moderator
one digest listing them with their moderate links (`PendingAlertEmail`). If nothing
is overdue, it sends nothing. `comments:pending` is the manual version of the same
check over SSH.

The same scheduler runs a second job weekly (Monday 9am Sydney): a digest of
comments auto-classified as `spam` in the last 7 days, lowest-score first, so a
false positive can still be caught and approved (`SpamDigestEmail`, see *Security
& spam defenses*). It too sends nothing in an empty week.

The scheduler only starts from `config.ru` under `RACK_ENV=production`, so rake
tasks and the test suite never spin up the thread or fire real emails. Two known
tradeoffs: it runs in the same process it watches, so it can't catch the app being
fully down (an external uptime monitor hitting `/up` covers that), and it's single-process, so
adding Puma workers later would mean duplicate digests.

## Backups & restore

The database is the one piece of state that isn't reproducible, so it's backed up
off-site to Cloudflare R2. The same in-process scheduler that runs the alerts runs a
backup daily at 3:30am Sydney (`config/scheduler.rb` → `SqliteBackup`); run it by hand
any time with `bundle exec rake comments:backup`.

Each run snapshots the live database with `VACUUM INTO` over its own short-lived
connection (WAL-safe, committed rows only, folded into one sidecar-free file), checks
it with `PRAGMA integrity_check`, gzips it, and uploads it to the
`blog-comments-backups` bucket under a timestamped key (`comments-<UTC>.sqlite3.gz`).
The upload is a plain S3 `PutObject` signed with SigV4 (`Sigv4Signer` + `BackupUploader`,
stdlib only; R2 speaks the S3 API, so there's no `aws-sdk` dependency). It retries a
5xx or network blip a few times but fails fast on a 4xx. Any failure is logged and
emailed to the moderator (`BackupFailureEmail`).

On the security side, the app holds a write-only, bucket-scoped R2 token (PutObject
only), so a compromise can't read other buckets or delete history. Retention is an R2
lifecycle rule that expires objects older than 30 days, configured Cloudflare-side
rather than in app code, so the app never needs delete permission. Keys are unique and
timestamped, so a stray write can't overwrite an existing backup.

One-time setup:

1. Create the `blog-comments-backups` R2 bucket.
2. Create a write-only R2 API token scoped to that bucket; put its `R2_ACCESS_KEY_ID`
   / `R2_SECRET_ACCESS_KEY` / `R2_ENDPOINT` in `.env.production`.
3. Add a lifecycle rule on the bucket to expire objects after 30 days.

### Restore

Restore is a deliberate, hands-on act, so it lives in a script you run from your
laptop, which has R2 read credentials (the server's token is write-only and can't list
or download). Put those creds in `~/.r2-credentials` as shell exports:
`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ENDPOINT_URL`, and
`AWS_DEFAULT_REGION=auto` (R2 has no regions, but the AWS CLI insists on one):

```sh
scripts/restore-backup.sh <droplet-ip> <ssh-key> [object-key]
```

It downloads the chosen backup (newest by default) and integrity-checks it locally,
then asks you to confirm by typing `yes`. On confirmation it connects over SSH, stops
the container, saves a `*.pre-restore-<ts>` copy of the current DB, swaps the new file
in (removing any stale `-wal`/`-shm` so SQLite can't replay an old WAL over it),
restarts, and waits for `/up`. If health doesn't return it prints recent logs and an
exact rollback command. The script's built-in defaults target the production box;
override `SSH_USER` / `APP_DIR` / `SERVICE` / `PORT` / `R2_CREDS` via the environment
(or an optional, gitignored `scripts/deploy.env`) for a different box, and set `FORCE=1`
to skip the prompt.

Two caveats. Approved comments are already baked into the built static site, so the
data uniquely at risk is un-moderated `pending` rows, and a daily snapshot is plenty
for that. The failure email also only covers a backup that *ran and errored*; a backup
that never runs (a dead scheduler) isn't caught in-app, which is what the external
`/up` uptime monitor is for.

## Security & spam defenses

- Approve-first moderation: nothing is public without the moderator's action.
- Honeypot: a CSS-hidden `homepage` field; if filled, the request returns a
  success-looking response but stores no row and sends no email.
- Content scoring (`SpamDetection` concern): a dependency-free heuristic runs as a
  `before_create`. It scores the free-text fields (`author_name`, `author_role`,
  `body`) for link/HTML/BBCode injection, URL shorteners, Telegram links,
  obfuscation (zero-width and Cyrillic runs), and an SEO/pharma/gambling/crypto
  phrase list. Over the threshold the comment is stored `spam`: never emailed,
  never published. The response is identical to a normal pending accept, so a bot
  learns nothing. Tuned for a dev audience: `author_website` is a real URL field so
  it's exempt from the URL/TLD signals, and fenced or inline code is stripped before
  the markup and URL checks so a pasted snippet won't bin, while the phrase scan
  still reads the full body so spam can't hide inside a code fence. The threshold is
  conservative, so one weak signal won't trip it. A false positive lands in `spam`
  rather than being silently dropped. To catch those, a weekly digest (Mon 09:00
  Sydney, `SpamDigestEmail`) emails any spam from the last 7 days, lowest-score first
  since those are the likeliest mistakes. Each entry links to its existing
  token-gated page, so a mis-flag is two clicks from approval, and
  `Comment.where(status: 'spam')` covers older history. This is inbox hygiene, not a
  security boundary: the publish path is already spam-proof (approve-first, escaped
  plain text, `nofollow ugc`).
- Per-IP rate limit: `rack-attack` throttles `POST /comments` to 5/60s.
- Request-size guard: bodies over 64 KB are rejected with `413` before parsing.
- `rel="nofollow ugc"` on links: removes the SEO backlink value that is the entire
  economic motive for comment spam.
- Unguessable moderation token in the approve/reject URLs; mutations are POST only
  (prefetch-safe).
- Sinatra's `HttpOrigin` protection is deliberately disabled (the POSTs are
  intentionally cross-origin); there are no sessions, so no CSRF surface.
- Dependency cooldown (supply-chain): a 7-day gate on newly published gems via
  Bundler's `cooldown` (`source "https://rubygems.org", cooldown: 7` in the
  `Gemfile`; needs Bundler 4.0.13+). Most account-takeover gem attacks are caught
  within days, so refusing versions younger than a week lets the crowd vet a
  release before we resolve to it. Use `bundle install --cooldown 0` to override
  for an urgent security patch. Not a defense against slow-burn malicious gems
  that go undetected for months.

## Roadmap

Deliberately out of scope for v1: threading/replies, editing a posted comment,
reply-notifications to commenters, captcha, markdown bodies, and an admin
dashboard.
