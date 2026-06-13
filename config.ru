# frozen_string_literal: true

require File.join(__dir__, 'app.rb')

# Memoize config on boot - crashes the process if any ENV vars are missing
AppConfig.current

run RackApp
