# frozen_string_literal: true

# The "new comment awaiting moderation" email
class ModerationEmail
  extend MailHelpers

  def self.deliver_for(comment)
    moderation_email = build_moderation_email(comment)
    AppMailer.deliver(moderation_email)
  end

  def self.build_moderation_email(comment)
    {
      from: ENV.fetch('RESEND_FROM_EMAIL'),
      to: ENV.fetch('MODERATION_NOTIFY_EMAIL'),
      subject: subject(comment),
      html: html(comment)
    }
  end

  def self.subject(comment)
    "New comment awaiting moderation on #{comment.post_slug}"
  end

  def self.html(comment)
    link = "#{ENV.fetch('APP_BASE_URL')}/moderate/#{comment.moderation_token}"
    <<~HTML
      <h2>New comment on #{escape_html comment.post_slug}</h2>
      <p><strong>#{escape_html comment.author_name}</strong>#{role_html(comment)}#{website_html(comment)}</p>
      <blockquote>#{escape_html comment.body}</blockquote>
      <p><a href="#{escape_html link}">Moderate this comment</a></p>
    HTML
  end

  def self.role_html(comment)
    return '' if comment.author_role.blank?

    " &mdash; #{escape_html comment.author_role}"
  end

  def self.website_html(comment)
    return '' if comment.author_website.blank?

    " (#{escape_html comment.author_website})"
  end
end
