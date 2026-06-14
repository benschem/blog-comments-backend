# frozen_string_literal: true

require 'spec_helper'

RSpec.describe R2Uploader do
  let(:config) do
    BackupConfig.build(
      'R2_ACCESS_KEY_ID' => 'access-key-id',
      'R2_SECRET_ACCESS_KEY' => 'secret-access-key',
      'R2_ENDPOINT' => 'https://acct.r2.cloudflarestorage.com'
    )
  end
  let(:now) { Time.utc(2026, 6, 14, 3, 30, 0) }
  let(:http) { instance_double(Net::HTTP) }

  def http_response(code, response_body = '')
    instance_double(Net::HTTPResponse, code: code, body: response_body)
  end

  # Net::HTTP.start yields the connection and returns the block's value (the response);
  # record every request that flows through so examples can assert on the signed result.
  def record_requests(into)
    allow(Net::HTTP).to receive(:start) { |*_args, &block| block.call(http) }
    allow(http).to receive(:request) do |req|
      into << req
      http_response('200')
    end
  end

  def upload
    described_class.put(key: 'comments-20260614T033000Z.sqlite3.gz', body: 'gzip-bytes',
                        content_type: 'application/gzip', config:, now:)
  end

  describe '.put' do
    context 'when the upload succeeds' do
      let(:request) do
        requests = []
        record_requests(requests)
        upload
        requests.first
      end

      it 'PUTs the object to its bucket-scoped URL with the right content type', :aggregate_failures do
        expect(request.method).to eq('PUT')
        expect(request.uri.to_s).to eq("#{config.r2_endpoint}/#{R2Uploader::BUCKET}/" \
                                       'comments-20260614T033000Z.sqlite3.gz')
        expect(request.body).to eq('gzip-bytes')
        expect(request['content-type']).to eq('application/gzip')
      end

      it 'attaches the SigV4 Authorization header from the signer' do
        expect(request['authorization']).to start_with(Sigv4Signer::ALGORITHM)
      end
    end
  end

  describe 'retry behaviour' do
    let(:uploader) do
      described_class.new(key: 'comments-20260614T033000Z.sqlite3.gz', body: 'gzip-bytes',
                          content_type: 'application/gzip', config:, now:)
    end

    # Hand back each queued outcome in turn; a class is raised, a response is returned
    def respond_with(*outcomes)
      queue = outcomes.dup
      allow(Net::HTTP).to receive(:start) { |*_args, &block| block.call(http) }
      allow(http).to receive(:request) do
        outcome = queue.shift
        outcome.is_a?(Class) ? raise(outcome) : outcome
      end
    end

    before { allow(uploader).to receive(:sleep) } # don't actually wait between retries

    it 'retries a transient 5xx and succeeds', :aggregate_failures do
      respond_with(http_response('503'), http_response('200'))

      expect { uploader.put }.not_to raise_error
      expect(http).to have_received(:request).twice
    end

    it 'retries a network blip and succeeds' do
      respond_with(Net::OpenTimeout, http_response('200'))

      expect { uploader.put }.not_to raise_error
    end

    it 'raises after exhausting attempts on a persistent 5xx', :aggregate_failures do
      respond_with(*Array.new(R2Uploader::UPLOAD_MAX_ATTEMPTS) { http_response('503') })

      expect { uploader.put }.to raise_error(R2Uploader::TransientUploadError)
      expect(http).to have_received(:request).exactly(R2Uploader::UPLOAD_MAX_ATTEMPTS).times
    end

    it 'fails fast on a 4xx without retrying (e.g. a bad token)', :aggregate_failures do
      respond_with(http_response('403', 'AccessDenied'))

      expect { uploader.put }.to raise_error(R2Uploader::UploadError, /403/)
      expect(http).to have_received(:request).once
    end
  end
end
