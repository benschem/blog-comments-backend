# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AppMailer do
  # A ready-made envelope — AppMailer is pure transport and doesn't care what
  # built it (that's ModerationEmail's job).
  let(:email) { { from: 'comments@benschem.dev', to: 'ben@benschem.dev', subject: 'Hi', html: '<p>Hi</p>' } }

  # The API key is read from ENV at call-time and set process-globally on Resend,
  # so swap it in and restore both afterwards.
  around do |example|
    original_api_key = Resend.api_key
    original_env_key = ENV.fetch('RESEND_API_KEY', nil)
    ENV['RESEND_API_KEY'] = 'test_key'
    example.run
  ensure
    ENV['RESEND_API_KEY'] = original_env_key
    Resend.api_key = original_api_key
  end

  describe '.deliver' do
    context 'when Resend accepts the email' do
      before do
        allow(Resend::Emails).to receive(:send).and_return({ id: 'email_1' })
        described_class.deliver(email)
      end

      it 'hands the envelope straight to Resend' do
        expect(Resend::Emails).to have_received(:send).with(email)
      end

      it 'authenticates with the configured API key' do
        expect(Resend.api_key).to eq('test_key')
      end
    end

    context 'when Resend raises' do
      before { allow(Resend::Emails).to receive(:send).and_raise(Resend::Error.new('boom')) }

      it 'logs loudly and re-raises so the failure is never silent' do
        expect { described_class.deliver(email) }
          .to raise_error(Resend::Error)
          .and output(/AppMailer/).to_stderr
      end
    end

    context 'when the send exceeds the timeout' do
      # Shrink the bound and make the send outlast it, so Timeout fires first and
      # the example stays fast and deterministic (no real-time sleeping waited on).
      before do
        stub_const('AppMailer::TIMEOUT_SECONDS', 0.05)
        allow(Resend::Emails).to receive(:send) { sleep 1 }
      end

      it 'aborts with a Timeout::Error rather than hanging, logged and re-raised' do
        expect { described_class.deliver(email) }
          .to raise_error(Timeout::Error)
          .and output(/AppMailer/).to_stderr
      end
    end
  end
end
