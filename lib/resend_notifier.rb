# frozen_string_literal: true

require 'resend'
require 'cgi'
require 'timeout'

# Sends the "new comment awaiting moderation" email via Resend. With no admin
# dashboard, this email *is* the moderation queue, so a delivery failure is
# logged loudly and re-raised rather than swallowed — a silently dropped mail
# would strand a comment in `pending` forever. The caller (POST /comments)
# rescues it so the commenter still gets a 201. Reads ENV at call-time so specs
# can swap the config cleanly.
module ResendNotifier
  # Bound the send so a hung Resend connection can't tie up a background worker
  # indefinitely. The resend gem wraps HTTParty and doesn't cleanly expose a
  # per-request timeout, so we wrap the call instead. A trip raises
  # Timeout::Error (a StandardError), which is logged and re-raised like any
  # other send failure — the caller's job swallows it and the `comments:pending`
  # digest is the backstop.
  TIMEOUT_SECONDS = 10

  module_function

  def notify(comment)
    Resend.api_key = ENV.fetch('RESEND_API_KEY', nil)
    Timeout.timeout(TIMEOUT_SECONDS) { Resend::Emails.send(message_for(comment)) }
  rescue StandardError => e
    warn '[ResendNotifier] failed to send moderation email for comment ' \
         "#{comment.id} on #{comment.post_slug.inspect}: #{e.class}: #{e.message}"
    raise
  end

  def message_for(comment)
    {
      from: ENV.fetch('RESEND_FROM_EMAIL'),
      to: ENV.fetch('MODERATION_NOTIFY_EMAIL'),
      subject: subject_for(comment),
      html: html_for(comment)
    }
  end

  def subject_for(comment)
    "New comment awaiting moderation on #{comment.post_slug}"
  end

  def html_for(comment)
    link = "#{ENV.fetch('APP_BASE_URL')}/moderate/#{comment.moderation_token}"
    <<~HTML
      <h2>New comment on #{escape_html comment.post_slug}</h2>
      <p><strong>#{escape_html comment.author_name}</strong>#{role_html(comment)}#{website_html(comment)}</p>
      <blockquote>#{escape_html comment.body}</blockquote>
      <p><a href="#{escape_html link}">Review, approve or reject this comment</a></p>
    HTML
  end

  # Optional metadata fragments — omitted entirely when the commenter left them blank.
  def role_html(comment)
    return '' if comment.author_role.blank?

    " &mdash; #{escape_html comment.author_role}"
  end

  def website_html(comment)
    return '' if comment.author_website.blank?

    " (#{escape_html comment.author_website})"
  end

  def escape_html(text)
    CGI.escapeHTML(text.to_s)
  end
end
