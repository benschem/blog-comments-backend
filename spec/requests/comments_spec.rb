# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Comments API', type: :request do
  describe 'POST /comments' do
    let(:valid_params) do
      { post_slug: 'hello-world', author_name: 'Ada', author_website: 'https://ada.example',
        author_role: 'Engineer', body: 'Nice post' }
    end

    # Stub the moderation email everywhere so no real send is attempted and we
    # can assert on whether the seam was reached. The submit enqueues a job that
    # runs inline in tests (see spec/support/sucker_punch.rb) and calls this.
    before { allow(ModerationEmail).to receive(:deliver_for) }

    context 'with valid params' do
      before { post '/comments', valid_params }

      it 'stores a pending comment with all the submitted fields' do
        expect(Comment.last).to have_attributes(
          post_slug: 'hello-world', author_name: 'Ada', author_website: 'https://ada.example',
          author_role: 'Engineer', body: 'Nice post', status: 'pending'
        )
      end

      it 'responds 201' do
        expect(last_response).to be_created
      end

      it 'notifies the moderator' do
        expect(ModerationEmail).to have_received(:deliver_for).with(Comment.last)
      end

      it 'never echoes the moderation token' do
        expect(last_response.body).not_to include(Comment.last.moderation_token)
      end
    end

    context 'when capturing the requester' do
      before do
        post '/comments', valid_params, 'HTTP_USER_AGENT' => 'RSpec UA', 'REMOTE_ADDR' => '203.0.113.5'
      end

      it 'records the ip and user agent' do
        expect(Comment.last).to have_attributes(ip_address: '203.0.113.5', user_agent: 'RSpec UA')
      end
    end

    context 'when the honeypot is filled' do
      let(:honeypot_params) { valid_params.merge(homepage: 'http://spam.example') }

      before do
        allow(AppLogger).to receive(:info)
        post '/comments', honeypot_params
      end

      it 'persists no comment' do
        expect(Comment.count).to eq(0)
      end

      it 'sends no email' do
        expect(ModerationEmail).not_to have_received(:deliver_for)
      end

      it 'responds with a success-looking 200' do
        expect(last_response).to be_ok
      end

      it 'logs the dropped submission at info level' do
        expect(AppLogger).to have_received(:info).with(/honeypot/i)
      end
    end

    context 'with invalid params' do
      before { post '/comments', valid_params.merge(body: '') }

      it 'persists no comment' do
        expect(Comment.count).to eq(0)
      end

      it 'responds 422 with the validation errors', :aggregate_failures do
        expect(last_response).to be_unprocessable
        expect(JSON.parse(last_response.body)).to have_key('errors')
      end

      it 'does not notify the moderator' do
        expect(ModerationEmail).not_to have_received(:deliver_for)
      end
    end

    context 'when the notifier raises' do
      before do
        allow(ModerationEmail).to receive(:deliver_for).and_raise(StandardError, 'mail down')
        post '/comments', valid_params
      end

      it 'still persists the comment' do
        expect(Comment.count).to eq(1)
      end

      it 'still responds 201' do
        expect(last_response).to be_created
      end
    end

    context 'when the per-IP rate limit is exceeded' do
      before { 6.times { post '/comments', valid_params } }

      it 'throttles the submission over the limit with 429' do
        expect(last_response.status).to eq(429)
      end
    end
  end

  describe 'GET /comments' do
    let(:slug) { 'my-post' }

    before do
      create(:comment, :approved, post_slug: slug, author_name: 'Old', created_at: 2.days.ago)
      create(:comment, :approved, post_slug: slug, author_name: 'New', created_at: 1.day.ago)
      create(:comment, :approved, post_slug: 'another-post') # wrong slug
      create(:comment, post_slug: slug)                      # right slug, still pending
      get '/comments', post_slug: slug
    end

    it 'responds with JSON' do
      expect(last_response.content_type).to include('application/json')
    end

    it 'returns only the approved comments for the slug, oldest first' do
      names = JSON.parse(last_response.body).map { |c| c['author_name'] }
      expect(names).to eq(%w[Old New])
    end

    it 'exposes only the public fields' do
      expect(JSON.parse(last_response.body).first.keys).to contain_exactly(
        'author_name', 'author_website', 'author_role', 'body', 'created_at'
      )
    end
  end
end
