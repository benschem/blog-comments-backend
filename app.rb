# frozen_string_literal: true

require 'bundler/setup'
Bundler.require(:default, ENV['RACK_ENV'] || :development)

require 'dotenv/load' unless ENV['RACK_ENV'] == 'production'
require 'rack'
require 'sinatra/base'
require 'sinatra/activerecord'
require 'active_support/cache'

# Middleware
require_relative 'app/middleware/reject_oversize_requests'

# Config
require_relative 'config/app_logger'
require_relative 'config/app_config'
require_relative 'config/rack_attack'

# Models
require_relative 'app/models/concerns/spam_detection'
require_relative 'app/models/comment'

# Lib
require_relative 'lib/netlify_build_hook'

# Mail
require_relative 'mailer/app_mailer'
require_relative 'mailer/mail_helpers'
require_relative 'mailer/mail/moderation_email'
require_relative 'mailer/mail/pending_alert_email'

# Jobs
require_relative 'app/jobs/notify_moderator_job'

# Controllers
require_relative 'app/controllers/base_controller'
require_relative 'app/controllers/health_controller'
require_relative 'app/controllers/comments_controller'
require_relative 'app/controllers/moderation_controller'

RackApp = Rack::Builder.new do
  use HealthController                # halts on /up, so the probe never reaches the logger below
  use Rack::CommonLogger, AppLogger   # access log for all real traffic, into the shared stdout sink
  use RejectOversizeRequests
  use Rack::Attack
  use CommentsController
  run ModerationController
end.to_app
