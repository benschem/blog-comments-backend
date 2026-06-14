# frozen_string_literal: true

require 'spec_helper'

require_relative '../../config/scheduler'

# Just ensure everything necessary is wired up correctly, no need to test rufus internals
RSpec.describe Scheduler do
  let(:scheduler) { instance_double(Rufus::Scheduler) }
  let(:jobs) { {} } # cron expression => the block scheduled for it

  before do
    described_class.instance_variable_set(:@start, nil) # clear the memo so .start re-runs
    allow(Rufus::Scheduler).to receive(:new).and_return(scheduler)
    allow(scheduler).to receive(:cron) { |expression, &block| jobs[expression] = block }
  end

  after { described_class.instance_variable_set(:@start, nil) }

  describe '.start' do
    before { described_class.start }

    it 'schedules a job for each configured cron' do
      expect(jobs.keys).to contain_exactly(
        described_class::STALE_COMMENTS_CRON,
        described_class::SPAM_DIGEST_CRON,
        described_class::BACKUP_CRON
      )
    end

    it 'sends the stale pending comment alert when its cron fires' do
      allow(PendingAlertEmail).to receive(:deliver_overdue)
      jobs[described_class::STALE_COMMENTS_CRON].call
      expect(PendingAlertEmail).to have_received(:deliver_overdue)
    end

    it 'sends the spam digest when its cron fires' do
      allow(SpamDigestEmail).to receive(:deliver_recent)
      jobs[described_class::SPAM_DIGEST_CRON].call
      expect(SpamDigestEmail).to have_received(:deliver_recent)
    end

    it 'runs the database backup when its cron fires' do
      allow(SqliteBackup).to receive(:run)
      jobs[described_class::BACKUP_CRON].call
      expect(SqliteBackup).to have_received(:run)
    end
  end
end
