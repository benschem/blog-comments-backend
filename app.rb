# frozen_string_literal: true

require 'bundler/setup'
Bundler.require(:default, ENV['RACK_ENV'] || :development)

require 'dotenv/load'
require 'sinatra/base'
require 'sinatra/activerecord'
require 'active_support/cache'

require_relative 'app/middleware/reject_oversize_requests'
require_relative 'config/rack_attack'

class App < Sinatra::Base
  register Sinatra::ActiveRecordExtension
  set :database_file, 'config/database.yml'

  set :protection, except: [:http_origin] # Allow cross-origin POSTs

  use RejectOversizeRequests
  use Rack::Attack
end

Dir[File.join(__dir__, 'app/models/*.rb')].each { require it }
Dir[File.join(__dir__, 'lib/*.rb')].each { require it }

require_relative 'mailer/app_mailer'
require_relative 'mailer/mail_helpers'
require_relative 'mailer/mail/moderation_email'

Dir[File.join(__dir__, 'app/jobs/*.rb')].each { require it }
Dir[File.join(__dir__, 'app/controllers/*.rb')].each { require it }
