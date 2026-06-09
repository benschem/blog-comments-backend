# frozen_string_literal: true

require 'bundler/setup'
Bundler.require(:default, ENV['RACK_ENV'] || :development)

require 'dotenv/load'
require 'sinatra/base'
require 'sinatra/activerecord'
require 'active_support/cache'

# Throttle comment submissions per IP to keep the DB from being flooded. The
# config is global to the Rack::Attack singleton (read per request), so it is
# defined once here at load; the `use Rack::Attack` that activates it lives in
# the App class below. In-memory store is fine for a single Puma process.
Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

Rack::Attack.throttle('comments/ip', limit: 5, period: 60) do |req|
  req.ip if req.post? && req.path == '/comments'
end

# The whole backend is one modular Sinatra app. Routes and helpers are added by
# reopening this class in app/controllers/*.rb, loaded at the bottom of this
# file. Cross-cutting config (DB, protection, body guard, throttle) lives here
# once and applies to every route, with no global Sinatra::Application in play.
class App < Sinatra::Base
  # Modular apps must register the extension explicitly (classic mode did this
  # for us). `set :database_file` then establishes the AR connection.
  register Sinatra::ActiveRecordExtension
  set :database_file, 'config/database.yml'

  # Allow the cross-origin POSTs from the static site
  set :protection, except: [:http_origin]

  # Reject oversized bodies before parsing them as a cheap insurance against
  # malicious clients trying to exhaust memory with a giant payload
  MAX_REQUEST_BYTES = 64 * 1024
  before do
    halt 413 if request.content_length.to_i > MAX_REQUEST_BYTES
  end

  use Rack::Attack
end

# Autoload models now that AR is connected
Dir[File.join(__dir__, 'app/models/*.rb')].each { require it }

# Load the integrations (Resend email, Netlify build hook)
Dir[File.join(__dir__, 'lib/*.rb')].each { require it }

# Load the background jobs. After lib/ (the jobs call into the integrations) and
# before the controllers that enqueue them.
Dir[File.join(__dir__, 'app/jobs/*.rb')].each { require it }

# Load the route handlers. Each file reopens `App` to add its helpers and
# routes, so this must run after the class is defined above.
Dir[File.join(__dir__, 'app/controllers/*.rb')].each { require it }
