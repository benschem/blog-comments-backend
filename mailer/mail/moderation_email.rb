# frozen_string_literal: true

# The "new comment awaiting moderation" email
class ModerationEmail
  include MailHelpers

  def self.deliver_for(comment, config: AppConfig.current)
    new(comment, config).deliver
  end

  def initialize(comment, config)
    @comment = comment
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
    "New comment awaiting moderation on #{@comment.post_slug}"
  end

  def html
    link = "#{@config.app_base_url}/moderate/#{@comment.moderation_token}"
    <<~HTML
      <h2>New comment on #{escape_html @comment.post_slug}</h2>
      <p><strong>#{escape_html @comment.author_name}</strong>#{role_html}#{website_html}</p>
      <blockquote>#{escape_html @comment.body}</blockquote>
      <p><a href="#{escape_html link}">Moderate this comment</a></p>
    HTML
  end

  def role_html
    return '' if @comment.author_role.blank?

    " &mdash; #{escape_html @comment.author_role}"
  end

  def website_html
    return '' if @comment.author_website.blank?

    " (#{escape_html @comment.author_website})"
  end
end
