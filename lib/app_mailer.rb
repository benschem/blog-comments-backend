# frozen_string_literal: true

require 'resend'
require 'timeout'

# Sends emails via Resend
class AppMailer
  TIMEOUT_SECONDS = 10

  def self.deliver(email)
    new.deliver(email)
  end

  def initialize
    # Fetches ENV at call-time so specs can swap the config cleanly
    @api_key = ENV.fetch('RESEND_API_KEY', nil)
  end

  def deliver(email)
    Resend.api_key = @api_key

    Timeout.timeout(TIMEOUT_SECONDS) do
      Resend::Emails.send(email)
    end
  rescue StandardError => e
    warn "[AppMailer] failed to send `#{email[:subject]}` to #{email[:to]}: #{e.class}: #{e.message}"
    raise
  end
end
