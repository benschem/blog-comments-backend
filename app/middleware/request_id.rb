# frozen_string_literal: true

require 'securerandom'

# Tags each request with a short ID
class RequestId
  X_REQ_ID_HEADER_KEY = 'X-Request-Id'
  REQUEST_ID_ENV_KEY = 'app.request_id'
  THREAD_KEY = :request_id

  # Any char that is NOT a letter, digit, underscore, period, or hyphen
  DISALLOWED_CHARS = /[^\w.-]/
  MAX_ID_LENGTH_CHARS = 64

  def initialize(app)
    @app = app
  end

  def call(env)
    inbound_id = sanitised_id_from_header(env)
    id = inbound_id.present? ? inbound_id : SecureRandom.hex(8)

    env[REQUEST_ID_ENV_KEY] = id
    Thread.current[THREAD_KEY] = id # Not everything can see the env, can't use a global because Puma is multi-threaded

    status, headers, body = @app.call(env)
    headers[X_REQ_ID_HEADER_KEY] = id
    [status, headers, body]
  ensure
    Thread.current[THREAD_KEY] = nil
  end

  private

  def sanitised_id_from_header(env)
    env['HTTP_X_REQUEST_ID'].to_s.gsub(DISALLOWED_CHARS, '')[0, MAX_ID_LENGTH_CHARS]
  end
end
