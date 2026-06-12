# frozen_string_literal: true

# Run sucker_punch jobs synchronously, in the calling thread, during tests. This
# makes `NotifyModeratorJob.perform_async` behave like the old inline call: the
# request specs can still assert on ModerationEmail and the work stays inside the
# example's DB transaction. Without it, perform_async would hand the job to a
# background thread and the assertions would race the response.
require 'sucker_punch/testing/inline'
