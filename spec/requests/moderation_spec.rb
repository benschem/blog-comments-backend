# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Moderation', type: :request do
  subject(:comment) { create(:comment) }

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

      it 'renders the approve and reject forms' do
        expect(last_response.body)
          .to include("/moderate/#{comment.moderation_token}/approve")
          .and include("/moderate/#{comment.moderation_token}/reject")
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
          allow(NetlifyBuildTrigger).to receive(:fire)
          post "/moderate/#{token}/approve"
        end

        it 'approves the comment' do
          expect(comment.reload.status).to eq('approved')
        end

        it 'fires the build hook' do
          expect(NetlifyBuildTrigger).to have_received(:fire)
        end
      end

      context 'when the build hook fails' do
        before do
          allow(NetlifyBuildTrigger).to receive(:fire).and_raise(StandardError, 'hook down')
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
        allow(NetlifyBuildTrigger).to receive(:fire)
        post "/moderate/#{token}/approve"
      end

      it 'responds 404' do
        expect(last_response).to be_not_found
      end

      it 'fires no build hook' do
        expect(NetlifyBuildTrigger).not_to have_received(:fire)
      end
    end
  end

  describe 'POST /moderate/:token/reject' do
    before do
      allow(NetlifyBuildTrigger).to receive(:fire)
      post "/moderate/#{token}/reject"
    end

    context 'with a known token' do
      let(:token) { comment.moderation_token }

      it 'rejects the comment' do
        expect(comment.reload.status).to eq('rejected')
      end

      it 'fires no build hook' do
        expect(NetlifyBuildTrigger).not_to have_received(:fire)
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
