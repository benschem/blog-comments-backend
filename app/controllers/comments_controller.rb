# frozen_string_literal: true

# Public comment endpoints: accept a submission (held for moderation) and serve
# a post's already-approved comments. Classic-style routes that delegate to
# Sinatra::Application; required from app.rb after `require 'sinatra'`.

# A submission always looks successful from the outside: the same minimal body
# is returned whether the comment was stored (201) or silently dropped as
# honeypot spam (200), so a bot learns nothing from the response.
PENDING_JSON = { status: 'pending' }.to_json

helpers do
  # Only the fields a commenter may set, plus the request metadata we capture
  # server-side. `status` is intentionally absent — the DB defaults it to
  # `pending`, so a forged `status=approved` param can never take effect.
  def submitted_comment_attributes
    {
      post_slug: params[:post_slug],
      author_name: params[:author_name],
      author_website: params[:author_website],
      author_role: params[:author_role],
      body: params[:body],
      ip_address: request.ip,
      user_agent: request.user_agent
    }
  end

  # The moderation email is best-effort: a delivery failure must never cost the
  # commenter their 201, so it is logged (ResendNotifier already warns) and
  # swallowed here. The CLI `comments:pending` task is the backstop.
  def notify_moderator(comment)
    ResendNotifier.notify(comment)
  rescue StandardError => e
    warn "[POST /comments] moderation email failed for ##{comment.id}: #{e.class}: #{e.message}"
  end
end

# Accept a new comment. Spam defence is layered in front of this: the 413 body
# guard and per-IP rack-attack throttle (app.rb), then the CSS-hidden `homepage`
# honeypot below. Real submissions are stored `pending` and the moderator mailed.
post '/comments' do
  content_type :json

  # Honeypot tripped: feign success, persist nothing, email no one. Log it (with
  # the IP) so the dropped spam is still visible — useful for spotting abusive
  # sources even though we never store the row.
  if params[:homepage].present?
    warn "[POST /comments] honeypot tripped from #{request.ip} " \
         "on #{params[:post_slug].inspect}; dropping the submission"
    halt 200, PENDING_JSON
  end

  comment = Comment.new(submitted_comment_attributes)

  if comment.save
    notify_moderator(comment)
    status 201
    PENDING_JSON
  else
    status 422
    { errors: comment.errors.full_messages }.to_json
  end
end

# Serve a post's approved comments, oldest first, public fields only — this is
# what the static site fetches at build time.
get '/comments' do
  content_type :json
  comments = Comment.approved.for_slug(params[:post_slug]).order(:created_at, :id)
  comments.map(&:public_attributes).to_json
end
