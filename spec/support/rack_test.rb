# frozen_string_literal: true

require 'rack/test'

# Rack::Test::Methods needs an `app` to drive; point it at the modular App.
module RackTestHelpers
  def app
    App
  end
end

RSpec.configure do |config|
  config.include Rack::Test::Methods
  config.include RackTestHelpers
end
