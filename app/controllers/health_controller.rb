# frozen_string_literal: true

# Check that both Puma is up and the database is connected
class HealthController < BaseController
  get '/up' do
    content_type :json

    begin
      Comment.connection.select_value('SELECT 1')
    rescue StandardError => e
      warn "[GET /up] database check failed: #{e.class}: #{e.message}"
      halt 503, { status: 'error' }.to_json
    end

    { status: 'ok' }.to_json
  end
end
