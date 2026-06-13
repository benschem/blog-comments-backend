# frozen_string_literal: true

require File.join(__dir__, 'app.rb')
require_relative 'config/scheduler'

# Memoize config on boot - crashes the process if any ENV vars are missing
AppConfig.current

Scheduler.start if ENV['RACK_ENV'] == 'production'

run RackApp
