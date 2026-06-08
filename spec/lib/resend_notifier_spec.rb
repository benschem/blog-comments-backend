# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ResendNotifier do
  let(:comment) do
    build(:comment,
          post_slug: 'hello-world',
          author_name: 'Ada',
          body: 'Nice post',
          moderation_token: 'tok_abc123')
  end

  # The notifier reads ENV and Resend.api_key at call-time, so swap in known
  # config and restore both afterwards (they are process-global, not per-example).
  around do |example|
    original_env = ENV.to_hash
    original_api_key = Resend.api_key
    ENV.update(
      'APP_BASE_URL' => 'https://comments.benschem.dev',
      'RESEND_API_KEY' => 'test_key',
      'RESEND_FROM_EMAIL' => 'comments@benschem.dev',
      'MODERATION_NOTIFY_EMAIL' => 'ben@benschem.dev'
    )
    example.run
  ensure
    ENV.replace(original_env)
    Resend.api_key = original_api_key
  end

  describe '.notify' do
    context 'when Resend accepts the email' do
      before do
        allow(Resend::Emails).to receive(:send).and_return({ id: 'email_1' })
        described_class.notify(comment)
      end

      it 'emails the moderation inbox with the right envelope and subject' do
        expect(Resend::Emails).to have_received(:send).with(
          hash_including(from: 'comments@benschem.dev', to: 'ben@benschem.dev',
                         subject: a_string_including('hello-world'))
        )
      end

      it 'includes the comment and a moderation link in the body' do
        expect(Resend::Emails).to have_received(:send).with(
          hash_including(html: a_string_including('Ada')
                               .and(a_string_including('Nice post'))
                               .and(a_string_including('https://comments.benschem.dev/moderate/tok_abc123')))
        )
      end
    end

    context 'with HTML in the comment body' do
      let(:comment) { build(:comment, body: '<script>alert(1)</script>', moderation_token: 'tok_x') }
      let(:sent) { {} }

      before do
        allow(Resend::Emails).to receive(:send) { |params| sent.merge!(params) }
        described_class.notify(comment)
      end

      it 'escapes HTML in the body', :aggregate_failures do
        expect(sent[:html]).to include('&lt;script&gt;')
        expect(sent[:html]).not_to include('<script>')
      end
    end

    context 'when Resend raises' do
      before { allow(Resend::Emails).to receive(:send).and_raise(Resend::Error.new('boom')) }

      it 'logs loudly and re-raises so the failure is never silent' do
        expect { described_class.notify(comment) }
          .to raise_error(Resend::Error)
          .and output(/ResendNotifier/).to_stderr
      end
    end
  end
end
