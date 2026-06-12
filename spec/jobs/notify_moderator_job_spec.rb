# frozen_string_literal: true

require 'spec_helper'

RSpec.describe NotifyModeratorJob do
  subject(:job) { described_class.new }

  let(:comment) { create(:comment) }

  describe '#perform' do
    it 'sends the moderation email for the comment' do
      allow(ModerationEmail).to receive(:deliver_for)
      job.perform(comment)
      expect(ModerationEmail).to have_received(:deliver_for).with(comment)
    end

    context 'when the email send raises' do
      before { allow(ModerationEmail).to receive(:deliver_for).and_raise(StandardError, 'mail down') }

      it 'swallows the error so a failed send never crashes the worker' do
        expect { job.perform(comment) }.not_to raise_error
      end

      it 'logs the failure for visibility' do
        expect { job.perform(comment) }.to output(/NotifyModeratorJob.*mail down/m).to_stderr
      end
    end
  end
end
