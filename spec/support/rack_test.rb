# frozen_string_literal: true

require 'rack/test'

# Rack::Test::Methods needs an `app` to drive; point it at the assembled stack
# (defined in app.rb) so specs exercise the same middleware pipeline as production.
module RackTestHelpers
  def app
    RackApp
  end
end

RSpec.configure do |config|
  config.include Rack::Test::Methods
  config.include RackTestHelpers
end
