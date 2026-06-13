# Single-stage build. The sqlite3 gem ships a precompiled native gem for
# x86_64/aarch64-linux-gnu (see Gemfile.lock PLATFORMS), so ruby:3.4.5-slim needs
# no build tools and no system libsqlite3 — the gem bundles its own.
FROM ruby:3.4.5-slim

# System packages: jemalloc (allocator) and tzdata (zoneinfo DB — slim ships none,
# so without it TZ can't resolve named zones and logs fall back to UTC).
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends libjemalloc2 tzdata \
 && rm -rf /var/lib/apt/lists/*

ENV RACK_ENV=production
ENV BUNDLE_DEPLOYMENT=1
ENV BUNDLE_WITHOUT="development:test"
ENV BUNDLE_PATH=/usr/local/bundle
# Local zone for log timestamps; %Z then tracks the AEST/AEDT DST switch (needs tzdata above).
ENV TZ=Australia/Sydney
# Preload jemalloc by soname (no path) so the dynamic linker resolves the correct
# arch-specific lib via ldconfig — works on both x86_64 and aarch64 builds.
ENV LD_PRELOAD=libjemalloc.so.2

WORKDIR /app

# Install gems first so the layer caches unless the lockfile changes.
COPY Gemfile Gemfile.lock .ruby-version ./
RUN bundle install

# App code.
COPY . .

# Run as a non-root user that owns the app and the DB mount point. If the host
# bind-mount UID mismatches and blocks DB writes, chown the host ./db to this
# user's UID, or drop the USER line to run as root.
RUN useradd --create-home --shell /usr/sbin/nologin app \
 && mkdir -p /app/db \
 && chown -R app:app /app
USER app

EXPOSE 9292

ENTRYPOINT ["bin/docker-entrypoint.sh"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
