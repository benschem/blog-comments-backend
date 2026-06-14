# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Moderation', type: :request do
  let(:comment) { create(:comment) }

  describe 'GET /moderate/:token' do
    before { get "/moderate/#{token}" }

    context 'with a known token' do
      let(:token) { comment.moderation_token }

      it 'responds 200' do
        expect(last_response).to be_ok
      end

      it 'leaves the comment pending' do
        expect(comment.reload.status).to eq('pending')
      end

      it 'renders the approve, reject and mark spam forms' do
        aggregate_failures do
          expect(last_response.body).to include("/moderate/#{comment.moderation_token}/approve")
          expect(last_response.body).to include("/moderate/#{comment.moderation_token}/reject")
          expect(last_response.body).to include("/moderate/#{comment.moderation_token}/mark_spam")
        end
      end
    end

    context 'with an unknown token' do
      let(:token) { 'does-not-exist' }

      it 'responds 404' do
        expect(last_response).to be_not_found
      end
    end
  end

  describe 'POST /moderate/:token/approve' do
    context 'with a known token' do
      let(:token) { comment.moderation_token }

      context 'when the build hook succeeds' do
        before do
          allow(BuildHook).to receive(:trigger)
          post "/moderate/#{token}/approve"
        end

        it 'approves the comment' do
          expect(comment.reload.status).to eq('approved')
        end

        it 'triggers the build hook' do
          expect(BuildHook).to have_received(:trigger)
        end

        it 'redirects back to the review page' do
          expect(last_response)
            .to be_redirect.and have_attributes(location: end_with("/moderate/#{token}"))
        end

        it 'shows the updated status after following the redirect' do
          follow_redirect!
          expect(last_response.body).to include('approved')
        end
      end

      context 'when the build hook fails' do
        before do
          allow(BuildHook).to receive(:trigger).and_raise(StandardError, 'hook down')
          post "/moderate/#{token}/approve"
        end

        it 'still approves the comment' do
          expect(comment.reload.status).to eq('approved')
        end
      end
    end

    context 'with an unknown token' do
      let(:token) { 'does-not-exist' }

      before do
        allow(BuildHook).to receive(:trigger)
        post "/moderate/#{token}/approve"
      end

      it 'responds 404' do
        expect(last_response).to be_not_found
      end

      it 'does not trigger the build hook' do
        expect(BuildHook).not_to have_received(:trigger)
      end
    end
  end

  describe 'POST /moderate/:token/reject' do
    before do
      allow(BuildHook).to receive(:trigger)
      post "/moderate/#{token}/reject"
    end

    context 'with a known token' do
      let(:token) { comment.moderation_token }

      it 'rejects the comment' do
        expect(comment.reload.status).to eq('rejected')
      end

      it 'does not trigger the build hook' do
        expect(BuildHook).not_to have_received(:trigger)
      end

      it 'redirects back to the review page' do
        expect(last_response)
          .to be_redirect.and have_attributes(location: end_with("/moderate/#{token}"))
      end

      it 'shows the updated status after following the redirect' do
        follow_redirect!
        expect(last_response.body).to include('rejected')
      end
    end

    context 'with an unknown token' do
      let(:token) { 'does-not-exist' }

      it 'responds 404' do
        expect(last_response).to be_not_found
      end
    end
  end

  describe 'POST /moderate/:token/mark_spam' do
    before do
      allow(BuildHook).to receive(:trigger)
      post "/moderate/#{token}/mark_spam"
    end

    context 'with a known token' do
      let(:token) { comment.moderation_token }

      it 'marks the comment as spam' do
        expect(comment.reload.status).to eq('spam')
      end

      it 'does not trigger the build hook' do
        expect(BuildHook).not_to have_received(:trigger)
      end

      it 'redirects back to the review page' do
        expect(last_response)
          .to be_redirect.and have_attributes(location: end_with("/moderate/#{token}"))
      end

      it 'shows the updated status after following the redirect' do
        follow_redirect!
        expect(last_response.body).to include('spam')
      end
    end

    context 'with an unknown token' do
      let(:token) { 'does-not-exist' }

      it 'responds 404' do
        expect(last_response).to be_not_found
      end
    end
  end
end
