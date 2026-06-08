# blog-comments-backend

A small self-hosted comments backend for a static site.

Unlike some of the existing options, it lets **anyone** comment without them
needing to login.

Built with **Sinatra + ActiveRecord + SQLite**, it sits on a VPS and feeds
approved comments into an [Astro](https://astro.build)site that bakes them into
HTML at build time.

## How it works

The site is static, so comments — inherently dynamic — are the awkward case.
The design resolves that with one core decision: **approve-first moderation**.

1. A visitor submits a comment via a no-JS HTML form (`POST /comments`). It is
   stored as `pending` and is **not** public.
2. The backend emails _me_ (via [Resend](https://resend.com)) with the comment
   and unguessable approve/reject links.
3. I click approve. The comment flips to `approved` and a **Netlify build hook**
   fires.
4. The site rebuilds, fetching approved comments at build time
   (`GET /comments?post_slug=…`) and baking them into static HTML.

Because nothing is ever public until I approve it, the system is **spam-proof by
construction** — no captcha, no email confirmation, no admin dashboard. The
email _is_ the moderation UI.

### Why these choices (short version)

- **Self-hosted backend, not giscus / comments-in-git** — those force commenters
  to have a GitHub account; the whole point is to let anyone comment.
- **Approve-first, not confirm-then-publish** — email confirmation is ~zero spam
  protection (bots have mailboxes). Inverting it makes spam impossible to publish.
- **Notify me, don't verify strangers** — notifying myself is one outbound
  request; verifying strangers is the whole expensive apparatus (deliverability,
  PII, confirm/expire state). So no commenter email is stored at all.
- **Bake at build, rebuild on approve** — keeps every page a zero-JS static
  document (Lighthouse-100, crawlable) and sidesteps adblockers, since reads
  happen server-side at build time.

## Data model

A single `comments` table. The columns:

- **`post_slug`** (string, not null) — keys comments to a post (slugs must stay stable).
- **`author_name`** (string, not null) — the only required public field.
- **`author_website`** (string, optional) — rendered as `rel="nofollow ugc"`.
- **`author_role`** (string, optional) — short job-title/role.
- **`body`** (text, not null) — **plain text**, escaped on render.
- **`status`** (string, not null, default `pending`) — enum, see below.
- **`moderation_token`** (string, not null, unique) — unguessable capability gating the approve/reject links.
- **`ip_address`** (string) — spam triage, never displayed.
- **`user_agent`** (text) — spam triage, never displayed.
- **`created_at` / `updated_at`** (datetime) — timestamps.

Notes:

- **`status` is an enum**, not a boolean: `pending / approved / spam / rejected`,
  so "rejected on purpose" is distinguishable from "not looked at yet".
- **No email / PII stored** — nothing to disclose, nothing to delete on request.
- `public_attributes` is an explicit allow-list (`author_name`, `author_website`,
  `author_role`, `body`, `created_at`) — the token, IP, user-agent and status are
  never served.
- Indexes: `[post_slug, status]` (covers the public read query) and a unique
  index on `moderation_token`.

## API

- **`POST /comments`** — submit a comment. Stored `pending`, notifies via Resend.
  Honeypot field `homepage` → silent success, no row. Throttled to 5/60s per IP.
- **`GET /comments?post_slug=…`** — approved comments for a post, ordered,
  `public_attributes` only (JSON).
- **`GET /moderate/:token`** — prefetch-safe confirm page with approve/reject
  forms. **Zero side effects.**
- **`POST /moderate/:token/approve`** — `approve!` the comment, then fire the
  Netlify build hook.
- **`POST /moderate/:token/reject`** — `reject!` the comment. No hook.

Moderation mutations happen on **POST**, not GET, because mail clients prefetch
GET links.

## Command-line moderation

The email links are the primary moderation UI, but the same actions are available
from the terminal as a fallback — handy over SSH on the VPS, or if a notification
email goes missing. All run via `bundle exec rake`:

- **`comments:pending`** — list the comments awaiting moderation, each with its
  id, local (AEST) timestamp, post, author and a body excerpt.
- **`comments:approve[<id>]`** — approve a comment by id, then fire the Netlify
  build hook. The approval persists even if the hook fails (it's reported, not
  fatal).
- **`comments:reject[<id>]`** — reject a comment by id. No hook.

```sh
bundle exec rake comments:pending
bundle exec rake 'comments:approve[42]'   # quote the brackets so the shell doesn't glob them
bundle exec rake 'comments:reject[42]'
```

Run `comments:pending` first to get the ids; approve/reject print the result and
abort with a clear message on an unknown or missing id.

## Project layout

```
.
├── app.rb                  # bootstrap: requires, DB config, middleware, autoload globs
├── config.ru               # Puma entry point → runs Sinatra::Application
├── Rakefile                # db:* tasks + comments:* CLI moderation tasks
├── config/database.yml     # per-environment SQLite config, chosen by RACK_ENV
├── app/
│   ├── models/comment.rb   # the Comment model
│   └── controllers/        # routes (classic-style blocks) — being built
├── db/
│   ├── migrate/            # migrations
│   └── schema.rb           # generated; databases are gitignored
├── lib/                    # ResendNotifier / NetlifyBuildTrigger — being built
└── spec/                   # RSpec + rack-test + factory_bot + database_cleaner
```

`app.rb` is the single setup point: it loads completely whether the entry point
is the server (`config.ru`) or rake (`Rakefile`). The route files use top-level
`get`/`post` blocks that delegate to `Sinatra::Application` and are `require`d
from `app.rb` after `require 'sinatra'`.

## Getting started

Requires Ruby **3.4.5** (pinned in `.ruby-version`).

```sh
bundle install

bundle exec rake db:create                  # create dev + test databases
bundle exec rake db:migrate                  # migrate dev
RACK_ENV=test bundle exec rake db:migrate    # migrate the test DB too

bundle exec rake db:seed                     # optional: sample comments for local dev

cp .env.example .env                         # then fill in the values below

bundle exec rackup                           # boot locally on :9292
```

### Tests & linting

```sh
bundle exec rspec     # run the suite (coverage via simplecov → coverage/)
bundle exec rubocop   # lint
```

### Environment variables

Copy `.env.example` to `.env` and set:

- **`RACK_ENV`** — `development` / `test` / `production`.
- **`APP_BASE_URL`** — base URL so moderation links in emails resolve.
- **`RESEND_API_KEY`** — Resend API key for moderation notifications.
- **`RESEND_FROM_EMAIL`** — sender address, e.g. `comments@benschem.dev`.
- **`MODERATION_NOTIFY_EMAIL`** — inbox that receives new-comment notifications.
- **`NETLIFY_BUILD_HOOK_URL`** — Netlify build hook fired on approve.
- **`TRUSTED_PROXY`** — optional; for `X-Forwarded-For` handling behind a proxy.

## Security & spam defenses

- **Approve-first moderation** — nothing is public without my action.
- **Honeypot** — a CSS-hidden `homepage` field; if filled, the request returns a
  success-looking response but stores no row and sends no email.
- **Per-IP rate limit** — `rack-attack` throttles `POST /comments` to 5/60s.
- **Request-size guard** — bodies over 64 KB are rejected with `413` before
  parsing.
- **`rel="nofollow ugc"` on links** — removes the SEO backlink value that is the
  entire economic motive for comment spam.
- **Unguessable moderation token** in the approve/reject URLs; mutations are POST
  only (prefetch-safe).
- Sinatra's `HttpOrigin` protection is deliberately disabled (the POSTs are
  intentionally cross-origin); there are no sessions, so no CSRF surface.

## Roadmap

**Deliberately out of scope for v1:** threading/replies, editing a posted
comment, reply-notifications to commenters, captcha, markdown bodies, and an
admin dashboard.
