# frozen_string_literal: true

# Shared configuration for every mounted controller
class BaseController < Sinatra::Base
  register Sinatra::ActiveRecordExtension
  # Pin root to the project root for relative settings (database_file below)
  set :root, File.expand_path('../..', __dir__)
  set :database_file, 'config/database.yml'

  set :protection, except: [:http_origin] # Allow cross-origin POSTs

  # Keep every response out of search indexes
  before { headers 'X-Robots-Tag' => 'noindex' }
end
