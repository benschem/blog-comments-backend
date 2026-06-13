# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RejectOversizeRequests do
  let(:downstream) { ->(_env) { [200, { 'content-type' => 'text/plain' }, ['ok']] } }
  let(:middleware) { described_class.new(downstream) }

  # Build a minimal POST env and force the Content-Length the middleware reads.
  def env_with_length(bytes)
    Rack::MockRequest.env_for('/comments', method: 'POST').merge('CONTENT_LENGTH' => bytes.to_s)
  end

  describe '#call' do
    context 'when the body is within the limit' do
      it 'passes the request through to the app', :aggregate_failures do
        status, _headers, body = middleware.call(env_with_length(1024))
        expect(status).to eq(200)
        expect(body).to eq(['ok'])
      end
    end

    context 'when the body exceeds the limit' do
      let(:oversized) { described_class::MAX_REQUEST_BYTES + 1 }

      before { allow(AppLogger).to receive(:info) }

      it 'rejects it with a 413 before reaching the app', :aggregate_failures do
        status, headers, body = middleware.call(env_with_length(oversized))
        expect(status).to eq(413)
        expect(body).to eq(['Payload Too Large'])
        expect(headers).to include('content-type' => 'text/plain')
      end

      it 'logs the rejection at info level with request context' do
        middleware.call(env_with_length(oversized))
        expect(AppLogger).to have_received(:info).with(/rejected oversized body/)
      end
    end
  end
end
