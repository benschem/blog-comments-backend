# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PendingAlertEmail do
  let(:config) { build_config_for_specs }

  # Capture the envelope handed to the transport instead of sending for real
  # (the trailing `**` swallows the config keyword the deliver_* methods pass on).
  let(:email) { {} }

  before { allow(AppMailer).to receive(:deliver) { |params, **| email.merge!(params) } }

  def moderate_url(comment)
    "#{config.app_base_url}/moderate/#{comment.moderation_token}"
  end

  describe '#deliver' do
    context 'with a single comment' do
      let(:comments) do
        [build(:comment, author_name: 'Ada', body: 'Nice post', moderation_token: 'tok_abc123')]
      end

      before { described_class.new(comments, config).deliver }

      it 'addresses the moderation inbox from the configured sender' do
        expect(email).to include(from: config.resend_from_email, to: config.moderation_notify_email)
      end

      it 'uses a singular subject naming the count' do
        expect(email[:subject]).to eq("#{comments.size} comment still awaiting moderation")
      end

      it 'lists the comment and its moderation link in the body' do
        comment = comments.first
        expect(email[:html])
          .to include(comment.author_name)
          .and include(comment.body)
          .and include(moderate_url(comment))
      end
    end

    context 'with several comments' do
      let(:comments) do
        [
          build(:comment, author_name: 'Ada', body: 'first', moderation_token: 'tok_1'),
          build(:comment, author_name: 'Grace', body: 'second', moderation_token: 'tok_2')
        ]
      end

      before { described_class.new(comments, config).deliver }

      it 'uses a plural subject naming the count' do
        expect(email[:subject]).to eq("#{comments.size} comments still awaiting moderation")
      end

      it 'lists every comment with its own moderation link', :aggregate_failures do
        expect(email[:html]).to include(comments.first.author_name).and include(comments.last.author_name)
        expect(email[:html])
          .to include(moderate_url(comments.first))
          .and include(moderate_url(comments.last))
      end
    end

    context 'with HTML in a comment' do
      let(:comments) { [build(:comment, body: '<script>alert(1)</script>', moderation_token: 'tok_x')] }

      before { described_class.new(comments, config).deliver }

      it 'escapes HTML in the body', :aggregate_failures do
        expect(email[:html]).to include(MailHelpers.escape_html(comments.first.body))
        expect(email[:html]).not_to include(comments.first.body)
      end
    end

    context 'with an empty set' do
      before { described_class.new([], config).deliver }

      it 'sends nothing rather than an empty list' do
        expect(AppMailer).not_to have_received(:deliver)
      end
    end
  end

  describe '.deliver_overdue' do
    let(:cutoff) { Comment::STALE_AFTER_HOURS.hours.ago }

    context 'when nothing is overdue' do
      before do
        create(:comment, created_at: cutoff + 1.hour)              # newer than the window
        create(:comment, :approved, created_at: cutoff - 1.hour)   # old but not pending
        described_class.deliver_overdue(config:)
      end

      it 'sends nothing' do
        expect(AppMailer).not_to have_received(:deliver)
      end
    end

    context 'when comments are overdue' do
      let(:overdue) { create(:comment, author_name: 'Overdue Olive', created_at: cutoff - 1.hour) }

      before do
        overdue
        create(:comment, created_at: cutoff + 1.hour)              # newer than the window, excluded
        create(:comment, :rejected, created_at: cutoff - 1.hour)   # not pending, excluded
        described_class.deliver_overdue(config:)
      end

      it 'emails only the overdue pending comments', :aggregate_failures do
        expect(AppMailer).to have_received(:deliver)
        expect(email[:subject]).to start_with('1 comment ') # the one overdue, not the excluded two
        expect(email[:html]).to include(overdue.author_name)
      end
    end

    context 'when a comment sits at the age boundary' do
      let(:just_over) { create(:comment, author_name: 'Just Over', created_at: cutoff - 1.minute) }
      let(:just_under) { create(:comment, author_name: 'Just Under', created_at: cutoff + 1.minute) }

      before do
        just_over
        just_under
        described_class.deliver_overdue(config:)
      end

      it 'includes a comment just past the threshold' do
        expect(email[:html]).to include(just_over.author_name)
      end

      it 'excludes a comment just under the threshold' do
        expect(email[:html]).not_to include(just_under.author_name)
      end
    end
  end
end
