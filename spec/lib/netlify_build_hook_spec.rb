# frozen_string_literal: true

require 'spec_helper'

RSpec.describe NetlifyBuildHook do
  around do |example|
    original = ENV.to_hash
    ENV['NETLIFY_BUILD_HOOK_URL'] = 'https://api.netlify.com/build_hooks/abc123'
    example.run
  ensure
    ENV.replace(original)
  end

  describe '.trigger' do
    let(:http) { instance_double(Net::HTTP) }

    context 'when the hook accepts the request' do
      before do
        allow(Net::HTTP).to receive(:start).and_yield(http)
        allow(http).to receive(:post)
        described_class.trigger
      end

      it 'opens a TLS connection to the hook host' do
        expect(Net::HTTP).to have_received(:start).with(
          'api.netlify.com', 443, hash_including(use_ssl: true)
        )
      end

      it 'POSTs an empty body to the hook path' do
        expect(http).to have_received(:post).with('/build_hooks/abc123', '')
      end
    end

    context 'when the connection fails' do
      before { allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED) }

      it 'does not swallow the error (the caller rescues)' do
        expect { described_class.trigger }.to raise_error(Errno::ECONNREFUSED)
      end
    end
  end
end
