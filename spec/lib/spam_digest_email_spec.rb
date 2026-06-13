# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpamDigestEmail do
  let(:config) { build_config_for_specs }

  # Capture the envelope handed to the transport instead of sending for real
  let(:email) { {} }

  before { allow(AppMailer).to receive(:deliver) { |params, **| email.merge!(params) } }

  describe '#deliver' do
    context 'with a single flagged comment' do
      let(:comments) do
        [build(:comment, :spam, author_name: 'Ada', body: 'viagra', moderation_token: 'tok_abc123')]
      end

      before { described_class.new(comments, config).deliver }

      it 'addresses the moderation inbox from the configured sender' do
        expect(email).to include(from: 'comments@benschem.dev', to: 'ben@benschem.dev')
      end

      it 'uses a singular subject naming the count' do
        expect(email[:subject]).to eq('1 comment auto-flagged as spam this week')
      end

      it 'lists the comment, its score and its moderation link', :aggregate_failures do
        expect(email[:html])
          .to include('Ada')
          .and include('score 0.4')
          .and include('https://comments.benschem.dev/moderate/tok_abc123')
      end
    end

    context 'with several comments' do
      let(:comments) do
        [
          build(:comment, :spam, author_name: 'Spammy Sam', body: 'viagra', moderation_token: 'tok_hi'),
          build(:comment, :spam, author_name: 'Benign Ben', body: 'Lovely write-up, thanks', moderation_token: 'tok_lo')
        ]
      end

      before { described_class.new(comments, config).deliver }

      it 'uses a plural subject naming the count' do
        expect(email[:subject]).to eq('2 comments auto-flagged as spam this week')
      end

      it 'orders the borderline (lowest-score) comment first' do
        expect(email[:html].index('Benign Ben')).to be < email[:html].index('Spammy Sam')
      end
    end

    context 'with HTML in a comment' do
      let(:comments) { [build(:comment, :spam, body: '<script>alert(1)</script>', moderation_token: 'tok_x')] }

      before { described_class.new(comments, config).deliver }

      it 'escapes HTML in the body', :aggregate_failures do
        expect(email[:html]).to include('&lt;script&gt;')
        expect(email[:html]).not_to include('<script>alert')
      end
    end

    context 'when more comments are flagged than the cap' do
      before do
        stub_const('SpamDigestEmail::MAX_LISTED', 1)
        comments = [
          build(:comment, :spam, author_name: 'Spammy Sam', body: 'viagra', moderation_token: 'tok_hi'),
          build(:comment, :spam, author_name: 'Benign Ben', body: 'thanks for this', moderation_token: 'tok_lo')
        ]
        described_class.new(comments, config).deliver
      end

      it 'lists the borderline one and notes the rest are hidden', :aggregate_failures do
        expect(email[:html]).to include('Benign Ben').and include('1 higher-confidence spam comment hidden')
        expect(email[:html]).not_to include('Spammy Sam')
      end
    end

    context 'with an empty set' do
      before { described_class.new([], config).deliver }

      it 'sends nothing rather than an empty digest' do
        expect(AppMailer).not_to have_received(:deliver)
      end
    end
  end

  describe '.deliver_recent' do
    context 'when nothing was flagged in the window' do
      before do
        create(:comment, :spam, created_at: 8.days.ago) # older than the window
        create(:comment, created_at: 1.day.ago) # recent but pending, not spam
        described_class.deliver_recent(config:)
      end

      it 'sends nothing' do
        expect(AppMailer).not_to have_received(:deliver)
      end
    end

    context 'when comments were flagged this week' do
      before do
        create(:comment, :spam, author_name: 'Recent Rita', created_at: 1.day.ago)
        create(:comment, :spam, author_name: 'Old Otto', created_at: 8.days.ago) # outside the window
        create(:comment, :approved, author_name: 'Fine Fiona', created_at: 1.day.ago) # not spam
        described_class.deliver_recent(config:)
      end

      it 'emails only the recently flagged spam', :aggregate_failures do
        expect(AppMailer).to have_received(:deliver)
        expect(email[:subject]).to eq('1 comment auto-flagged as spam this week')
        expect(email[:html]).to include('Recent Rita')
        expect(email[:html]).not_to include('Old Otto')
        expect(email[:html]).not_to include('Fine Fiona')
      end
    end
  end
end
