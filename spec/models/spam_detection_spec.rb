# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpamDetection, type: :model do
  # Exercised through Comment, which includes the concern.
  subject(:comment) do
    build(:comment, author_name: author_name, author_role: author_role,
                    author_website: author_website, body: body)
  end

  let(:author_name) { 'Jane Smith' }
  let(:author_role) { 'Reader' }
  let(:author_website) { nil }
  let(:body) { 'Really enjoyed this post, thanks for writing it up.' }

  describe '#spam_score' do
    context 'with a legitimate comment' do
      it 'scores below the spam threshold' do
        expect(comment.spam_score).to be < described_class::SPAM_THRESHOLD
      end
    end

    context 'with a normal website link supplied' do
      let(:author_website) { 'https://jane.example.com' }

      it 'does not penalise the dedicated website field' do
        expect(comment.spam_score).to be < described_class::SPAM_THRESHOLD
      end
    end

    context 'with a URL in the name' do
      let(:author_name) { 'Visit https://spam.com' }

      it 'adds to the score' do
        expect(comment.spam_score).to be >= 0.8
      end
    end

    context 'with link/injection HTML in the body' do
      let(:body) { '<a href="https://evil.com">Click here</a>' }

      it 'scores it hard' do
        expect(comment.spam_score).to be >= 0.8
      end
    end

    context 'with a benign structural HTML snippet (a dev discussing markup)' do
      let(:body) { 'You can wrap it in a <div class="card"> and it lines up. Is that the right approach?' }

      it 'adds only a weak signal that cannot bin on its own', :aggregate_failures do
        expect(comment.spam_score).to be >= 0.3
        expect(comment.spam_score).to be < described_class::SPAM_THRESHOLD
      end
    end

    context 'with BBCode in the body' do
      let(:body) { '[url=https://evil.com]Click here[/url]' }

      it 'scores it hard as a forum-spam fingerprint' do
        expect(comment.spam_score).to be >= 0.8
      end
    end

    context 'with an HTML/JS snippet inside a fenced code block (a dev sharing code)' do
      let(:body) do
        "Here's how I wired the tag up:\n\n```html\n" \
          "<script src=\"https://cdn.example.com/app.js\"></script>\n" \
          "<a href=\"https://example.com/login\">Log in</a>\n```\n\nDoes that look right?"
      end

      # Without code-stripping this is <script>+<a href> (0.8) plus two URLs (0.3) = 1.1, a bin.
      it 'does not score the fenced markup or URLs' do
        expect(comment.spam_score).to be < described_class::SPAM_THRESHOLD
      end
    end

    context 'with an HTML tag mentioned in inline code' do
      let(:body) { 'You forgot the `<script>` tag and a stray `<iframe>` — add the script before </body>.' }

      it 'does not score inline code as markup' do
        expect(comment.spam_score).to be < described_class::SPAM_THRESHOLD
      end
    end

    context 'with spam prose hidden inside a code fence' do
      let(:body) { "```\nI visited your site. Our SEO services boost your ranking with backlinks.\n```" }

      it 'still scores the prose, since fences do not exempt the phrase list' do
        expect(comment.spam_score).to be >= described_class::SPAM_THRESHOLD
      end
    end

    context 'with a Telegram link' do
      let(:body) { 'Contact me at t.me/spambot for details' }

      it 'adds to the score' do
        expect(comment.spam_score).to be >= 0.8
      end
    end

    context 'with several URLs in the body' do
      let(:body) { 'See https://a.com/ and https://b.com/ and https://c.com/ now' }

      it 'adds to the score for each extra URL' do
        expect(comment.spam_score).to be >= 0.6
      end
    end

    context 'with a suspicious TLD on the website' do
      let(:author_website) { 'https://payday-loans.xyz/' }

      it 'adds to the score' do
        expect(comment.spam_score).to be >= 0.3
      end
    end

    context 'with SEO spam phrases' do
      let(:body) { 'I visited your site and our SEO services can boost your ranking with quality backlinks' }

      it 'scores above the spam threshold' do
        expect(comment.spam_score).to be >= described_class::SPAM_THRESHOLD
      end
    end

    context 'with a mostly-uppercase body' do
      let(:body) { 'BUY OUR AMAZING PRODUCTS NOW THEY ARE THE BEST DEAL EVER' }

      it 'adds to the score' do
        expect(comment.spam_score).to be >= 0.4
      end
    end

    context 'with zero-width unicode characters' do
      let(:body) { "Hidden\u200Bcharacters\u200Bin the text here" }

      it 'adds to the score' do
        expect(comment.spam_score).to be >= 0.8
      end
    end
  end

  describe 'the detect_spam callback' do
    context 'when the score crosses the threshold' do
      let(:body) { 'I visited your site. Our SEO services boost your ranking. Buy backlinks at https://spam.xyz/ now.' }

      it 'stores the comment as spam' do
        comment.save!
        expect(comment).to be_spam
      end
    end

    context 'when the score is below the threshold' do
      it 'leaves the default pending status' do
        comment.save!
        expect(comment.status).to eq('pending')
      end
    end
  end
end
