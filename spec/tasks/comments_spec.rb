# frozen_string_literal: true

require 'spec_helper'

# `type: :task` pulls in RakeTaskHelpers from spec/support/rake.rb
RSpec.describe 'comments rake tasks', type: :task do
  let(:comment) { create(:comment) }

  describe 'comments:pending' do
    let(:task_output) { run_task('comments:pending') }

    context 'with no pending comments' do
      it 'reports an empty queue' do
        expect(task_output).to include('No comments awaiting moderation')
      end
    end

    context 'with pending comments' do
      before { comment }

      it 'lists each pending comment', :aggregate_failures do
        expect(task_output).to include(comment.id.to_s)
        expect(task_output).to include(comment.author_name)
      end
    end
  end

  describe 'comments:approve' do
    let(:task_output) { run_task('comments:approve', comment.id) }

    context 'when the rebuild succeeds' do
      before do
        allow(NetlifyBuildHook).to receive(:trigger)
        task_output
      end

      it 'approves the comment' do
        expect(comment.reload.status).to eq('approved')
      end

      it 'triggers a site rebuild' do
        expect(NetlifyBuildHook).to have_received(:trigger)
      end
    end

    context 'when the rebuild fails' do
      before do
        allow(NetlifyBuildHook).to receive(:trigger).and_raise(StandardError, 'hook down')
        task_output
      end

      it 'approves the comment' do
        expect(comment.reload.status).to eq('approved')
      end

      it 'reports the failed site rebuild' do
        expect(task_output).to include('site rebuild failed')
      end
    end

    context 'with an unknown id' do
      let(:unknown_id) { Comment.maximum(:id).to_i + 1 }

      it 'aborts' do
        expect { run_task('comments:approve', unknown_id) }.to raise_error(SystemExit)
      end
    end
  end

  describe 'comments:reject' do
    before do
      allow(NetlifyBuildHook).to receive(:trigger)
      run_task('comments:reject', comment.id)
    end

    it 'rejects the comment' do
      expect(comment.reload.status).to eq('rejected')
    end

    it 'does not trigger a site rebuild' do
      expect(NetlifyBuildHook).not_to have_received(:trigger)
    end
  end

  describe 'comments:mark_spam' do
    before do
      allow(NetlifyBuildHook).to receive(:trigger)
      run_task('comments:mark_spam', comment.id)
    end

    it 'marks the comment as spam' do
      expect(comment.reload.status).to eq('spam')
    end

    it 'does not trigger a site rebuild' do
      expect(NetlifyBuildHook).not_to have_received(:trigger)
    end
  end
end
