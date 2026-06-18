# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RequestLogger do
  # A downstream app returning a configurable response triple.
  def app_returning(status, headers = { 'content-length' => '142' }, body = ['ok'])
    ->(_env) { [status, headers, body] }
  end

  def env_for(path = '/comments?post_slug=hello-world', headers = {})
    Rack::MockRequest.env_for(path, method: 'GET', 'REMOTE_ADDR' => '203.0.113.7').merge(headers)
  end

  def call(app, env = env_for)
    described_class.new(app).call(env)
  end

  describe '#call' do
    it 'logs an info access line with method, path, status, size, duration and IP' do
      allow(AppLogger).to receive(:info)
      call(app_returning(200))
      expect(AppLogger).to have_received(:info).with(
        %r{\A\[GET /comments\?post_slug=hello-world\] 200 142B \(\d+\.\d+ms\) from 203\.0\.113\.7\z}
      )
    end

    it 'returns the downstream response triple unchanged', :aggregate_failures do
      allow(AppLogger).to receive(:info)
      triple = [200, { 'content-length' => '142' }, ['ok']]
      status, headers, body = call(->(_env) { triple })
      expect([status, headers, body]).to eq(triple)
    end

    context 'when the response is a client error' do
      it 'logs at warn level' do
        allow(AppLogger).to receive(:warn)
        call(app_returning(404))
        expect(AppLogger).to have_received(:warn).with(%r{\[GET /comments\?post_slug=hello-world\] 404 })
      end
    end

    context 'when the response is a server error' do
      it 'logs at error level' do
        allow(AppLogger).to receive(:error)
        call(app_returning(500))
        expect(AppLogger).to have_received(:error).with(%r{\[GET /comments\?post_slug=hello-world\] 500 })
      end
    end

    context 'when the response has no Content-Length' do
      it 'logs the size as a dash' do
        allow(AppLogger).to receive(:info)
        call(app_returning(200, { 'content-type' => 'text/plain' }))
        expect(AppLogger).to have_received(:info).with(/\] 200 -B \(/)
      end
    end

    context 'when the path contains control characters' do
      it 'escapes them so the log line cannot be forged' do
        allow(AppLogger).to receive(:info)
        env = env_for.merge('PATH_INFO' => "/comments\r\nINJECTED", 'QUERY_STRING' => '')
        call(app_returning(200), env)
        expect(AppLogger).to have_received(:info).with(%r{\[GET /comments\?\?INJECTED\]})
      end
    end

    context 'when the downstream app raises' do
      it 'propagates the error and logs nothing', :aggregate_failures do
        allow(AppLogger).to receive(:info)
        expect { call(->(_env) { raise 'boom' }) }.to raise_error('boom')
        expect(AppLogger).not_to have_received(:info)
      end
    end
  end
end
