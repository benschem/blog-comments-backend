# frozen_string_literal: true

# Public comment endpoints: accept comments (held for moderation) and serve a
# post's already-approved comments.
class CommentsController < BaseController
  PENDING_JSON = { status: 'pending' }.to_json

  helpers do
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

    def notify_moderator(comment)
      NotifyModeratorJob.perform_async(comment)
    end

    def honeypot_tripped?
      params[:homepage].present?
    end
  end

  # Accept a new comment
  post '/comments' do
    content_type :json

    if honeypot_tripped?
      AppLogger.info "[POST /comments] honeypot tripped from #{request.ip} " \
                     "on #{params[:post_slug].inspect}; dropping the submission"
      halt 200, PENDING_JSON # Feign success, persist nothing, email no one
    end

    comment = Comment.new(submitted_comment_attributes)

    if comment.save
      # Auto-classified spam is stored for triage but never emailed or published.
      # The response is identical to a real pending accept so the bot learns nothing.
      if comment.spam?
        AppLogger.info "[POST /comments] auto-classified spam from #{request.ip} " \
                       "on #{params[:post_slug].inspect}; stored, not notifying"
      else
        notify_moderator(comment)
      end
      status 201
      PENDING_JSON
    else
      status 422
      { errors: comment.errors.full_messages }.to_json
    end
  end

  # Serve a post's approved comments, oldest first, public fields only
  # What the static site fetches at build time
  get '/comments' do
    content_type :json
    comments = Comment.approved.for_slug(params[:post_slug]).order(:created_at, :id)
    comments.map(&:public_attributes).to_json
  end
end
