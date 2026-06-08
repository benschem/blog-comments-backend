# frozen_string_literal: true

require 'bundler/setup'
Bundler.require(:default, ENV['RACK_ENV'] || :development)

require 'dotenv/load'
require 'sinatra'
require 'sinatra/activerecord'

set :database_file, 'config/database.yml'

# Allow the cross-origin POSTs from the static site
set :protection, except: [:http_origin]

# Reject oversized bodies before parsing them as a cheap insurance against
# malicious clients trying to exhaust memory with a giant payload
MAX_REQUEST_BYTES = 64 * 1024
before do
  halt 413 if request.content_length.to_i > MAX_REQUEST_BYTES
end

# Throttle comment submissions per IP to keep the DB from being flooded
# In-memory store is fine for a single Puma process
require 'active_support/cache'
Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

Rack::Attack.throttle('comments/ip', limit: 5, period: 60) do |req|
  req.ip if req.post? && req.path == '/comments'
end

use Rack::Attack

# Autoload models now that AR is connected
Dir[File.join(__dir__, 'app/models/*.rb')].each { require it }
