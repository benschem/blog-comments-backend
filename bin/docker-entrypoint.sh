#!/bin/sh
set -e

# db:create is a no-op if the database already exists; db:migrate is idempotent.
# Both boot the app (via db:load_config -> require './app'), so every required
# ENV var must already be set or this step crashes before Puma starts.
bundle exec rake db:create db:migrate

# Hand off to CMD (puma), keeping it as PID 1 so signals reach it directly.
exec "$@"
