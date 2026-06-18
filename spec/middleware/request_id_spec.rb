# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RequestId do
  let(:downstream) do
    # Echo back whatever the middleware stashed so we can assert on it.
    lambda do |env|
      [200, { 'content-type' => 'text/plain' },
       [env[described_class::REQUEST_ID_ENV_KEY], Thread.current[described_class::THREAD_KEY]]]
    end
  end

  let(:middleware) { described_class.new(downstream) }

  def env_for(headers = {})
    Rack::MockRequest.env_for('/comments', method: 'POST').merge(headers)
  end

  after { Thread.current[described_class::THREAD_KEY] = nil }

  describe '#call' do
    it 'exposes the ID on both the env and the thread-local', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      _status, headers, body = middleware.call(env_for)
      id = headers[described_class::X_REQ_ID_HEADER_KEY
    ]
      env_id, thread_id = body

      expect(env_id).to eq(id)
      expect(thread_id).to eq(id)
    end

    context 'when the inbound request has a valid X-Request-Id' do
      it 'reuses it unchanged' do
        _status, headers, = middleware.call(env_for('HTTP_X_REQUEST_ID' => 'abc-123'))
        expect(headers[described_class::X_REQ_ID_HEADER_KEY
        ]).to eq('abc-123')
      end
    end

    context 'when the inbound request has an invalid X-Request-Id' do
      it 'strips disallowed characters' do
        _status, headers, = middleware.call(env_for('HTTP_X_REQUEST_ID' => "ab c\n<script>"))
        expect(headers[described_class::X_REQ_ID_HEADER_KEY
        ]).to eq('abcscript')
      end

      it "caps the length if it's too long" do
        _status, headers, = middleware.call(env_for('HTTP_X_REQUEST_ID' => 'a' * 200))
        expect(headers[described_class::X_REQ_ID_HEADER_KEY
      ].length).to eq(described_class::MAX_ID_LENGTH_CHARS)
      end

      it 'falls back to a generated ID when the stripped inbound one has no usable characters' do
        _status, headers, = middleware.call(env_for('HTTP_X_REQUEST_ID' => '!!!'))
        expect(headers[described_class::X_REQ_ID_HEADER_KEY
        ]).to match(/\A[0-9a-f]{16}\z/)
      end
    end

    context 'when the inbound request does not have an X-Request-Id' do
      it 'generates a random ID' do
        _status, headers, = middleware.call(env_for({}))
        expect(headers[described_class::X_REQ_ID_HEADER_KEY
        ]).to match(/\A[0-9a-f]{16}\z/)
      end
    end

    it 'clears the thread-local after the request so it does not leak' do
      middleware.call(env_for)
      expect(Thread.current[described_class::THREAD_KEY]).to be_nil
    end

    it 'clears the thread-local even when the app raises', :aggregate_failures do
      boom = ->(_env) { raise 'boom' }
      expect { described_class.new(boom).call(env_for) }.to raise_error('boom')
      expect(Thread.current[described_class::THREAD_KEY]).to be_nil
    end
  end
end
