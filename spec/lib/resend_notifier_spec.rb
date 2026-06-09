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

    context 'when the send exceeds the timeout' do
      # Shrink the bound and make the send outlast it, so Timeout fires first and
      # the example stays fast and deterministic (no real-time sleeping waited on).
      before do
        stub_const('ResendNotifier::TIMEOUT_SECONDS', 0.05)
        allow(Resend::Emails).to receive(:send) { sleep 1 }
      end

      it 'aborts with a Timeout::Error rather than hanging, logged and re-raised' do
        expect { described_class.notify(comment) }
          .to raise_error(Timeout::Error)
          .and output(/ResendNotifier/).to_stderr
      end
    end

    context 'with optional author metadata' do
      let(:sent) { {} }

      before do
        allow(Resend::Emails).to receive(:send) { |params| sent.merge!(params) }
        described_class.notify(comment)
      end

      context 'when the role and website are present' do
        let(:comment) { build(:comment, author_role: 'Staff Engineer', author_website: 'https://ada.example') }

        it 'shows them next to the name', :aggregate_failures do
          expect(sent[:html]).to include('&mdash; Staff Engineer')
          expect(sent[:html]).to include('(https://ada.example)')
        end
      end

      context 'when the role and website are blank' do
        let(:comment) { build(:comment, author_role: '', author_website: nil) }

        it 'leaves out the dash and parens', :aggregate_failures do
          expect(sent[:html]).not_to include('&mdash;')
          expect(sent[:html]).not_to include('(')
        end
      end

      context 'with HTML in the role and website' do
        let(:comment) { build(:comment, author_role: '<b>boss</b>', author_website: '<i>site</i>') }

        it 'escapes them', :aggregate_failures do
          expect(sent[:html]).to include('&lt;b&gt;boss&lt;/b&gt;')
          expect(sent[:html]).to include('&lt;i&gt;site&lt;/i&gt;')
          expect(sent[:html]).not_to include('<b>boss</b>')
        end
      end
    end
  end
end
