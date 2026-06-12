# frozen_string_literal: true

# Reject oversized requests that are most likely spam/malicious
class RejectOversizeRequests
  MAX_REQUEST_BYTES = 64 * 1024 # 64 KB is ~64,000 characters or ~10,000 words

  def initialize(app)
    @app = app
  end

  def call(env)
    req = Rack::Request.new(env)

    if oversized?(req)
      warn log_message(req)
      return [413, { 'content-type' => 'text/plain' }, ['Payload Too Large']]
    end

    @app.call(env)
  end

  def oversized?(req)
    req.content_length.to_i > MAX_REQUEST_BYTES
  end

  def log_message(req)
    "[#{req.request_method} #{req.path}] rejected oversized body " \
      "(#{req.content_length} bytes > #{MAX_REQUEST_BYTES}) from #{req.ip}"
  end
end
