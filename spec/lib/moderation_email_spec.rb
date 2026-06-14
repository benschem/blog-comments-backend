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

  let(:config) { build_config_for_specs }

  def moderate_url(comment)
    "#{config.app_base_url}/moderate/#{comment.moderation_token}"
  end

  describe '.deliver_for' do
    # Capture the envelope handed to the transport instead of sending for real
    # (the trailing `**` swallows the config keyword deliver_for passes through).
    let(:email) { {} }

    before { allow(AppMailer).to receive(:deliver) { |params, **| email.merge!(params) } }

    context 'with a typical comment' do
      before { described_class.deliver_for(comment, config:) }

      it 'addresses the moderation inbox with a subject naming the post', :aggregate_failures do
        expect(email).to include(from: config.resend_from_email, to: config.moderation_notify_email)
        expect(email[:subject]).to include(comment.post_slug)
      end

      it 'includes the comment and a moderation link in the body' do
        expect(email[:html])
          .to include(comment.author_name)
          .and include(comment.body)
          .and include(moderate_url(comment))
      end
    end

    context 'with HTML in the comment body' do
      let(:comment) { build(:comment, body: '<script>alert(1)</script>', moderation_token: 'tok_x') }

      before { described_class.deliver_for(comment, config:) }

      it 'escapes HTML in the body', :aggregate_failures do
        expect(email[:html]).to include(MailHelpers.escape_html(comment.body))
        expect(email[:html]).not_to include(comment.body)
      end
    end

    context 'with optional author metadata' do
      before { described_class.deliver_for(comment, config:) }

      context 'when the role and website are present' do
        let(:comment) { build(:comment, author_role: 'Staff Engineer', author_website: 'https://ada.example') }

        it 'shows them next to the name', :aggregate_failures do
          expect(email[:html]).to include("&mdash; #{comment.author_role}")
          expect(email[:html]).to include("(#{comment.author_website})")
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
          expect(email[:html]).to include(MailHelpers.escape_html(comment.author_role))
          expect(email[:html]).to include(MailHelpers.escape_html(comment.author_website))
          expect(email[:html]).not_to include(comment.author_role)
        end
      end
    end
  end
end
