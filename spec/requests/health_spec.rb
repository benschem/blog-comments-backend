# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Healthcheck', type: :request do
  describe 'GET /up' do
    context 'when the database is reachable' do
      before { get '/up' }

      it 'responds 200' do
        expect(last_response).to be_ok
      end

      it 'returns JSON' do
        expect(last_response.content_type).to include('application/json')
      end

      it 'reports an ok status' do
        expect(JSON.parse(last_response.body)).to eq('status' => 'ok')
      end
    end

    context 'when the database check fails' do
      before do
        allow(Comment).to receive(:connection).and_raise(ActiveRecord::ConnectionNotEstablished)
        get '/up'
      end

      it 'responds 503' do
        expect(last_response.status).to eq(503)
      end

      it 'reports an error status' do
        expect(JSON.parse(last_response.body)).to eq('status' => 'error')
      end
    end

    context 'when hit repeatedly' do
      before { 10.times { get '/up' } }

      it 'is not subject to the per-IP throttle' do
        expect(last_response).to be_ok
      end
    end
  end
end
