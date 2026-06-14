# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Comment do
  subject(:comment) { build(:comment) }

  describe 'validations' do
    before { comment.validate }

    context 'without a post_slug' do
      subject(:comment) { build(:comment, post_slug: nil) }

      it('is invalid') { expect(comment.errors[:post_slug]).to be_present }
    end

    context 'without an author_name' do
      subject(:comment) { build(:comment, author_name: nil) }

      it('is invalid') { expect(comment.errors[:author_name]).to be_present }
    end

    context 'without a body' do
      subject(:comment) { build(:comment, body: nil) }

      it('is invalid') { expect(comment.errors[:body]).to be_present }
    end

    context 'without an author_website' do
      subject(:comment) { build(:comment, author_website: nil) }

      it('is valid') { is_expected.to be_valid }
    end

    context 'without an author_role' do
      subject(:comment) { build(:comment, author_role: nil) }

      it('is valid') { is_expected.to be_valid }
    end

    context 'with a too-long post_slug' do
      subject(:comment) { build(:comment, post_slug: 'a' * 201) }

      it('is invalid') { expect(comment.errors[:post_slug]).to be_present }
    end

    context 'with a too-long author_name' do
      subject(:comment) { build(:comment, author_name: 'a' * 101) }

      it('is invalid') { expect(comment.errors[:author_name]).to be_present }
    end

    context 'with a too-long author_role' do
      subject(:comment) { build(:comment, author_role: 'a' * 101) }

      it('is invalid') { expect(comment.errors[:author_role]).to be_present }
    end

    context 'with a too-long body' do
      subject(:comment) { build(:comment, body: 'a' * 5001) }

      it('is invalid') { expect(comment.errors[:body]).to be_present }
    end

    context 'with a body length at the limit' do
      subject(:comment) { build(:comment, body: 'a' * 5000) }

      it('is valid') { is_expected.to be_valid }
    end

    context 'with an unknown status' do
      subject(:comment) { build(:comment, status: 'bogus') }

      it('is invalid') { expect(comment.errors[:status]).to be_present }
    end

    context 'with an http author_website' do
      subject(:comment) { build(:comment, author_website: 'http://example.com') }

      it('is valid') { is_expected.to be_valid }
    end

    context 'with an https author_website' do
      subject(:comment) { build(:comment, author_website: 'https://example.com') }

      it('is valid') { is_expected.to be_valid }
    end

    context 'with a javascript-scheme author_website' do
      subject(:comment) { build(:comment, author_website: 'javascript:alert(1)') }

      it('is invalid') { expect(comment.errors[:author_website]).to be_present }
    end

    context 'with a scheme-less author_website' do
      subject(:comment) { build(:comment, author_website: 'example.com') }

      it('is invalid') { expect(comment.errors[:author_website]).to be_present }
    end

    context 'with an ftp-scheme author_website' do
      subject(:comment) { build(:comment, author_website: 'ftp://example.com') }

      it('is invalid') { expect(comment.errors[:author_website]).to be_present }
    end
  end

  describe 'creation side effects' do
    subject(:comment) { create(:comment) }

    it 'moderation_token is populated on create' do
      expect(comment.moderation_token).to be_present
    end

    it 'status defaults to pending on create' do
      expect(comment.status).to eq('pending')
    end
  end

  describe 'scopes' do
    describe '.approved' do
      let!(:approved) { create(:comment, :approved) }

      before do
        create(:comment) # pending
        create(:comment, :rejected)
      end

      it 'returns only approved comments' do
        expect(described_class.approved).to contain_exactly(approved)
      end
    end

    describe '.for_slug' do
      let!(:mine) { create(:comment, post_slug: 'hello-world') }

      before { create(:comment, post_slug: 'other-post') }

      it 'returns only comments for that slug' do
        expect(described_class.for_slug('hello-world')).to contain_exactly(mine)
      end
    end

    describe '.spam' do
      let!(:spammy) { create(:comment, :spam) }

      before do
        create(:comment) # pending
        create(:comment, :approved)
      end

      it 'returns only spam comments' do
        expect(described_class.spam).to contain_exactly(spammy)
      end
    end

    describe '.pending' do
      let!(:waiting) { create(:comment) }

      before do
        create(:comment, :approved)
        create(:comment, :spam)
      end

      it 'returns only pending comments' do
        expect(described_class.pending).to contain_exactly(waiting)
      end
    end

    describe '.stale_pending' do
      let(:cutoff) { described_class::STALE_AFTER_HOURS.hours.ago }
      let!(:stale_comment) { create(:comment, created_at: cutoff - 1.hour) }
      let!(:older_stale_comment) { create(:comment, created_at: cutoff - 1.day) }

      before do
        create(:comment, created_at: cutoff + 1.hour) # pending but not yet stale
        create(:comment, :approved, created_at: cutoff - 1.day) # old but not pending
      end

      it 'returns pending comments past the stale threshold, oldest first' do
        expect(described_class.stale_pending).to eq([older_stale_comment, stale_comment])
      end
    end

    describe '.recent_spam' do
      let(:cutoff) { described_class::RECENT_SPAM_DAYS.days.ago }
      let!(:newer_spam) { create(:comment, :spam, created_at: cutoff + 1.hour) }
      let!(:older_spam) { create(:comment, :spam, created_at: cutoff + 1.minute) }

      before do
        create(:comment, :spam, created_at: cutoff - 1.hour) # older than the window
        create(:comment, :approved, created_at: cutoff + 1.hour) # recent but not spam
      end

      it 'returns spam within the window, newest first' do
        expect(described_class.recent_spam).to eq([newer_spam, older_spam])
      end
    end
  end

  describe 'the comments shown on a post' do
    let(:slug) { 'my-post' }
    let!(:older) { create(:comment, :approved, post_slug: slug, created_at: 2.days.ago) }
    let!(:newer) { create(:comment, :approved, post_slug: slug, created_at: 1.day.ago) }

    before do
      create(:comment, :approved, post_slug: 'another-post') # wrong slug
      create(:comment, post_slug: slug) # pending, not yet approved
    end

    it 'are the approved ones for that slug, oldest first' do
      shown = described_class.approved.for_slug(slug).order(:created_at, :id)
      expect(shown).to eq([older, newer])
    end
  end

  describe 'instance methods' do
    describe '#approve!' do
      subject(:comment) { create(:comment) }

      it 'moves a pending comment to approved' do
        expect { comment.approve! }
          .to change { comment.reload.status }.from('pending').to('approved')
      end
    end

    describe '#reject!' do
      subject(:comment) { create(:comment) }

      it 'moves a pending comment to rejected' do
        expect { comment.reject! }
          .to change { comment.reload.status }.from('pending').to('rejected')
      end
    end

    describe '#mark_spam!' do
      subject(:comment) { create(:comment) }

      it 'moves a pending comment to spam' do
        expect { comment.mark_spam! }
          .to change { comment.reload.status }.from('pending').to('spam')
      end
    end

    describe '#spam?' do
      context 'when the comment is spam' do
        subject(:comment) { build(:comment, :spam) }

        it('is true') { expect(comment.spam?).to be(true) }
      end

      context 'when the comment is not spam' do
        subject(:comment) { build(:comment, :approved) }

        it('is false') { expect(comment.spam?).to be(false) }
      end
    end

    describe '#public_attributes' do
      subject(:comment) do
        create(:comment, :approved,
               author_name: 'Ada',
               author_website: 'https://ada.example',
               author_role: 'Engineer',
               body: 'Nice post')
      end

      it 'exposes only the public fields' do
        expect(comment.public_attributes.keys).to contain_exactly(
          :author_name, :author_website, :author_role, :body, :created_at
        )
      end

      it "returns each field's stored value" do # rubocop:disable RSpec/ExampleLength
        expect(comment.public_attributes).to include(
          author_name: 'Ada',
          author_website: 'https://ada.example',
          author_role: 'Engineer',
          body: 'Nice post'
        )
      end
    end
  end
end
