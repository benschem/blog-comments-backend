# frozen_string_literal: true

# Sends the "new comment awaiting moderation" email off the request thread, so a
# commenter's POST /comments returns immediately instead of blocking on the
# Resend round-trip (which has no enforced timeout). sucker_punch runs `perform`
# in an in-process thread pool (its default two workers) — dependency-light and
# requiring no separate process, but the queue is **in-memory and non-durable**:
# a job lost to a crash, deploy or restart is *not* retried. That gap is
# deliberately backstopped by the `comments:pending` digest, so a dropped email
# can never strand a comment permanently.
#
# It operates only on already-loaded attributes of the passed-in comment, so the
# worker thread never touches the database and the ActiveRecord connection pool
# is never involved — which is why the comment is passed by object, not by id.
class NotifyModeratorJob
  include SuckerPunch::Job

  def perform(comment)
    ResendNotifier.notify(comment)
  rescue StandardError => e
    # Best-effort, mirroring the old inline rescue. ResendNotifier already warns
    # loudly and re-raises; we swallow here so a failed send never crashes the
    # worker (nor propagates in inline test mode, where perform runs directly).
    # The digest is the real safety net.
    warn "[NotifyModeratorJob] moderation email failed for ##{comment.id}: #{e.class}: #{e.message}"
  end
end
