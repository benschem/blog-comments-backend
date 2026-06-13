# frozen_string_literal: true

require 'resend'
require 'timeout'

# Sends emails via Resend
class AppMailer
  TIMEOUT_SECONDS = 10

  def self.deliver(email, config: AppConfig.current)
    new(config).deliver(email)
  end

  def initialize(config)
    @api_key = config.resend_api_key
  end

  def deliver(email)
    Resend.api_key = @api_key

    Timeout.timeout(TIMEOUT_SECONDS) do
      Resend::Emails.send(email)
    end
  rescue StandardError => e
    AppLogger.error "[AppMailer] failed to send `#{email[:subject]}` to #{email[:to]}: #{e.class}: #{e.message}"
    raise
  end
end
