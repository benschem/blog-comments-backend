# frozen_string_literal: true

Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

Rack::Attack.throttle('comments/ip', limit: 5, period: 60) do |req|
  req.ip if req.post? && req.path == '/comments'
end
