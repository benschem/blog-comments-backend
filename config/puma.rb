# frozen_string_literal: true

# Bind on all interfaces inside the container; compose only publishes the port to
# 127.0.0.1 on the host, so the app stays reachable only via the local reverse proxy.
bind 'tcp://0.0.0.0:9292'

environment ENV.fetch('RACK_ENV', 'production')

# Match the ActiveRecord pool (5, in config/database.yml) so every request thread
# can hold a DB connection without queueing on the pool.
threads_count = Integer(ENV.fetch('RAILS_MAX_THREADS', 5))
threads threads_count, threads_count

# Single process — do NOT cluster. sucker_punch runs NotifyModeratorJob on an
# in-process thread pool; clustered workers would each fork their own in-memory
# queue, so jobs would be split/duplicated and lost on a worker restart. SQLite's
# single writer is also happier with one process.
workers 0
