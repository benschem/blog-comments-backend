# frozen_string_literal: true

# Sends the "new comment awaiting moderation" email off the request thread
class NotifyModeratorJob
  # sucker_punch is an in-memory queue, so lost jobs can't be retried
  include SuckerPunch::Job

  # Worker thread never touches the database so comment can be passed by object
  def perform(comment)
    ModerationEmail.deliver_for(comment)
  rescue StandardError => e
    AppLogger.error "[NotifyModeratorJob] moderation email failed for ##{comment.id}: #{e.class}: #{e.message}"
  end
end
