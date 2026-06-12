# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ModerationEmail do
  let(:comment) do
    build(:comment,
          post_slug: 'hello-world',
          author_name: 'Ada',
          body: 'Nice post',
          moderation_token: 'tok_abc123')
  end

  # The envelope reads ENV at call-time, so swap in known config and restore it.
  around do |example|
    original_env = ENV.to_hash
    ENV.update(
      'APP_BASE_URL' => 'https://comments.benschem.dev',
      'RESEND_FROM_EMAIL' => 'comments@benschem.dev',
      'MODERATION_NOTIFY_EMAIL' => 'ben@benschem.dev'
    )
    example.run
  ensure
    ENV.replace(original_env)
  end

  describe '.deliver_for' do
    # Capture the envelope handed to the transport instead of sending for real.
    let(:email) { {} }

    before { allow(AppMailer).to receive(:deliver) { |params| email.merge!(params) } }

    context 'with a typical comment' do
      before { described_class.deliver_for(comment) }

      it 'addresses the moderation inbox with a subject naming the post', :aggregate_failures do
        expect(email).to include(from: 'comments@benschem.dev', to: 'ben@benschem.dev')
        expect(email[:subject]).to include('hello-world')
      end

      it 'includes the comment and a moderation link in the body' do
        expect(email[:html])
          .to include('Ada')
          .and include('Nice post')
          .and include('https://comments.benschem.dev/moderate/tok_abc123')
      end
    end

    context 'with HTML in the comment body' do
      let(:comment) { build(:comment, body: '<script>alert(1)</script>', moderation_token: 'tok_x') }

      before { described_class.deliver_for(comment) }

      it 'escapes HTML in the body', :aggregate_failures do
        expect(email[:html]).to include('&lt;script&gt;')
        expect(email[:html]).not_to include('<script>')
      end
    end

    context 'with optional author metadata' do
      before { described_class.deliver_for(comment) }

      context 'when the role and website are present' do
        let(:comment) { build(:comment, author_role: 'Staff Engineer', author_website: 'https://ada.example') }

        it 'shows them next to the name', :aggregate_failures do
          expect(email[:html]).to include('&mdash; Staff Engineer')
          expect(email[:html]).to include('(https://ada.example)')
        end
      end

      context 'when the role and website are blank' do
        let(:comment) { build(:comment, author_role: '', author_website: nil) }

        it 'leaves out the dash and parens', :aggregate_failures do
          expect(email[:html]).not_to include('&mdash;')
          expect(email[:html]).not_to include('(')
        end
      end

      context 'with HTML in the role and website' do
        let(:comment) { build(:comment, author_role: '<b>boss</b>', author_website: '<i>site</i>') }

        it 'escapes them', :aggregate_failures do
          expect(email[:html]).to include('&lt;b&gt;boss&lt;/b&gt;')
          expect(email[:html]).to include('&lt;i&gt;site&lt;/i&gt;')
          expect(email[:html]).not_to include('<b>boss</b>')
        end
      end
    end
  end
end
