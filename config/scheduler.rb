# frozen_string_literal: true

# In-process scheduler on a wall-clock cron
#
## Single-process caveat: rufus fires once per process. The app runs one Puma
## process today (config/database.yml pool: 5 == Puma's default thread count), so
## one email per run. If Puma workers are ever added, each worker would fire this
## and the moderator would get duplicate digests — gate it to a single worker then
module Scheduler
  # Twice daily, pinned to Sydney
  STALE_COMMENTS_CRON = '0 8,20 * * * Australia/Sydney'

  # Memoised so a stray second call can't start a duplicate thread, and so the
  # running scheduler stays referenced (avoid GC) for the life of the process
  def self.start
    @start ||= Rufus::Scheduler.new.tap do |scheduler|
      # Periodically sweep for stale comments and email any to moderator
      scheduler.cron(STALE_COMMENTS_CRON) { PendingAlertEmail.deliver_overdue }
    end
  end
end
