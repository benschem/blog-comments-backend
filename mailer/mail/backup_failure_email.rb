# frozen_string_literal: true

# Emails the moderator when a scheduled database backup raises
class BackupFailureEmail
  include MailHelpers

  def self.deliver_for(error, config: AppConfig.current)
    new(error, config).deliver
  end

  def initialize(error, config)
    @error = error
    @config = config
  end

  def deliver
    AppMailer.deliver(envelope, config: @config)
  end

  private

  def envelope
    {
      from: @config.resend_from_email,
      to: @config.moderation_notify_email,
      subject: subject,
      html: html
    }
  end

  def subject
    '[Blog comments backend]: A scheduled database backup failed'
  end

  def html
    <<~HTML
      <h2>Database backup failed</h2>
      <p>The scheduled SQLite &rarr; R2 backup did not complete.</p>
      <p><strong>#{escape_html @error.class}</strong>: #{escape_html @error.message}</p>
      <p>At #{occurred_at}. It will retry on the next scheduled run. Investigate if it repeats.</p>
    HTML
  end

  def occurred_at
    Time.now.in_time_zone('Australia/Sydney').strftime('%-d %b %Y, %-I:%M%p %Z')
  end
end
