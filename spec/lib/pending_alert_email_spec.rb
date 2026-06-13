# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PendingAlertEmail do
  let(:config) { build_config_for_specs }

  # Capture the envelope handed to the transport instead of sending for real
  # (the trailing `**` swallows the config keyword the deliver_* methods pass on).
  let(:email) { {} }

  before { allow(AppMailer).to receive(:deliver) { |params, **| email.merge!(params) } }

  describe '#deliver' do
    context 'with a single comment' do
      let(:comments) do
        [build(:comment, author_name: 'Ada', body: 'Nice post', moderation_token: 'tok_abc123')]
      end

      before { described_class.new(comments, config).deliver }

      it 'addresses the moderation inbox from the configured sender' do
        expect(email).to include(from: 'comments@benschem.dev', to: 'ben@benschem.dev')
      end

      it 'uses a singular subject naming the count' do
        expect(email[:subject]).to eq('1 comment still awaiting moderation')
      end

      it 'lists the comment and its moderation link in the body' do
        expect(email[:html])
          .to include('Ada')
          .and include('Nice post')
          .and include('https://comments.benschem.dev/moderate/tok_abc123')
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
        expect(email[:subject]).to eq('2 comments still awaiting moderation')
      end

      it 'lists every comment with its own moderation link', :aggregate_failures do
        expect(email[:html]).to include('Ada').and include('Grace')
        expect(email[:html])
          .to include('https://comments.benschem.dev/moderate/tok_1')
          .and include('https://comments.benschem.dev/moderate/tok_2')
      end
    end

    context 'with HTML in a comment' do
      let(:comments) { [build(:comment, body: '<script>alert(1)</script>', moderation_token: 'tok_x')] }

      before { described_class.new(comments, config).deliver }

      it 'escapes HTML in the body', :aggregate_failures do
        expect(email[:html]).to include('&lt;script&gt;')
        expect(email[:html]).not_to include('<script>')
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
    let(:cutoff) { described_class::OVERDUE_AFTER_HOURS.hours.ago }

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
      before do
        create(:comment, author_name: 'Overdue Olive', created_at: cutoff - 1.hour)
        create(:comment, created_at: cutoff + 1.hour)              # newer than the window, excluded
        create(:comment, :rejected, created_at: cutoff - 1.hour)   # not pending, excluded
        described_class.deliver_overdue(config:)
      end

      it 'emails only the overdue pending comments', :aggregate_failures do
        expect(AppMailer).to have_received(:deliver)
        expect(email[:subject]).to eq('1 comment still awaiting moderation')
        expect(email[:html]).to include('Overdue Olive')
      end
    end

    context 'when a comment sits at the age boundary' do
      before do
        create(:comment, author_name: 'Just Over', created_at: cutoff - 1.minute)
        create(:comment, author_name: 'Just Under', created_at: cutoff + 1.minute)
        described_class.deliver_overdue(config:)
      end

      it 'includes a comment just past the threshold' do
        expect(email[:html]).to include('Just Over')
      end

      it 'excludes a comment just under the threshold' do
        expect(email[:html]).not_to include('Just Under')
      end
    end
  end
end
