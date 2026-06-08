# frozen_string_literal: true

# Rack::Attack's throttle counter is global in the process, so clear it before
# each example to stop the count leaking across specs and trippping the limit
RSpec.configure do |config|
  config.before { Rack::Attack.cache.store.clear }
end
