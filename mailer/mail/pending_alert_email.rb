# frozen_string_literal: true

# An email listing every comment that is still `pending` after the age threshold
class PendingAlertEmail
  include MailHelpers

  OVERDUE_AFTER_HOURS = 24

  def self.deliver_overdue(config: AppConfig.current)
    new(Comment.still_pending_after(OVERDUE_AFTER_HOURS.hours), config).deliver
  end

  def initialize(comments, config)
    @comments = comments
    @config = config
  end

  def deliver
    return if @comments.empty? # Don't email if nothing is overdue

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
    "#{@comments.size} #{'comment'.pluralize(@comments.size)} still awaiting moderation"
  end

  def html
    <<~HTML
      <h2>#{@comments.size} #{'comment'.pluralize(@comments.size)} still awaiting moderation</h2>
      <ul>
        #{@comments.map { |comment| list_item(comment) }.join("\n  ")}
      </ul>
    HTML
  end

  def list_item(comment)
    link = "#{@config.app_base_url}/moderate/#{comment.moderation_token}"
    "<li><strong>#{escape_html comment.author_name}</strong> on " \
      "#{escape_html comment.post_slug}: " \
      "#{escape_html comment.body.truncate(100)} " \
      "&mdash; <a href=\"#{escape_html link}\">Moderate</a></li>"
  end
end
