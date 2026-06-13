# frozen_string_literal: true

# A weekly digest of comments the scorer auto-classified as `spam`, so a false
# positive can still be caught
class SpamDigestEmail
  include MailHelpers

  RECENT_WITHIN = 7.days
  MAX_LISTED = 50

  def self.deliver_recent(config: AppConfig.current)
    new(Comment.spam_since(RECENT_WITHIN.ago), config).deliver
  end

  def initialize(comments, config)
    @comments = comments.to_a
    @config = config
  end

  def deliver
    return if @comments.empty? # No spam this week - no email

    AppMailer.deliver(envelope, config: @config)
  end

  private

  # Lowest score first: the borderline comments a human should actually re-check.
  def ranked
    @ranked ||= @comments.sort_by(&:spam_score)
  end

  def listed
    ranked.first(MAX_LISTED)
  end

  def envelope
    { from: @config.resend_from_email, to: @config.moderation_notify_email, subject:, html: }
  end

  def subject
    "#{@comments.size} #{'comment'.pluralize(@comments.size)} auto-flagged as spam this week"
  end

  def html
    <<~HTML
      <h2>#{subject}</h2>
      <p>Listed lowest-score first — the most likely false positives. Open one to approve it if it isn't spam.</p>
      <ul>
        #{listed.map { |comment| list_item(comment) }.join("\n  ")}
      </ul>
      #{overflow_note}
    HTML
  end

  def overflow_note
    hidden = @comments.size - listed.size
    return '' if hidden.zero?

    "<p>#{hidden} higher-confidence spam #{'comment'.pluralize(hidden)} hidden — " \
      'use the CLI to review the rest.</p>'
  end

  def list_item(comment)
    link = "#{@config.app_base_url}/moderate/#{comment.moderation_token}"
    "<li><strong>score #{format('%.1f', comment.spam_score)}</strong> &mdash; " \
      "<strong>#{escape_html comment.author_name}</strong> on " \
      "#{escape_html comment.post_slug}: " \
      "#{escape_html comment.body.truncate(100)} " \
      "&mdash; <a href=\"#{escape_html link}\">Review</a></li>"
  end
end
