# frozen_string_literal: true

require 'spec_helper'

RSpec.describe NotifyModeratorJob do
  subject(:job) { described_class.new }

  let(:comment) { create(:comment) }

  describe '#perform' do
    it 'sends the moderation email for the comment' do
      allow(ResendNotifier).to receive(:notify)
      job.perform(comment)
      expect(ResendNotifier).to have_received(:notify).with(comment)
    end

    context 'when the notifier raises' do
      before { allow(ResendNotifier).to receive(:notify).and_raise(StandardError, 'mail down') }

      it 'swallows the error so a failed send never crashes the worker' do
        expect { job.perform(comment) }.not_to raise_error
      end

      it 'logs the failure for visibility' do
        expect { job.perform(comment) }.to output(/NotifyModeratorJob.*mail down/m).to_stderr
      end
    end
  end
end
