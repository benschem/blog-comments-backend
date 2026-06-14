# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Sigv4Signer do
  let(:config) do
    BackupConfig.build(
      'R2_ACCESS_KEY_ID' => 'access-key-id',
      'R2_SECRET_ACCESS_KEY' => 'secret-access-key',
      'R2_ENDPOINT' => 'https://acct.r2.cloudflarestorage.com'
    )
  end
  let(:now) { Time.utc(2026, 6, 14, 3, 30, 0) }
  let(:uri) { URI.parse('https://acct.r2.cloudflarestorage.com/blog-comments-backups/object.gz') }

  def headers(body: 'gzip-bytes')
    described_class.new(config:, http_method: 'PUT', uri:, body:, now:).headers
  end

  it 'hashes the body into the x-amz-content-sha256 header' do
    expect(headers['X-Amz-Content-Sha256']).to eq(Digest::SHA256.hexdigest('gzip-bytes'))
  end

  it 'stamps the request time as a basic ISO-8601 instant' do
    expect(headers['X-Amz-Date']).to eq('20260614T033000Z')
  end

  it 'builds a well-formed SigV4 Authorization header' do
    scope = "20260614/#{described_class::REGION}/#{described_class::SERVICE}/aws4_request"
    pattern = "#{described_class::ALGORITHM} Credential=#{config.r2_access_key_id}/#{scope}, " \
              "SignedHeaders=#{described_class::SIGNED_HEADERS}, Signature=\\h{64}"
    expect(headers['Authorization']).to match(/\A#{pattern}\z/)
  end

  it 'signs identical inputs identically' do
    first = headers['Authorization']
    second = headers['Authorization']
    expect(first).to eq(second)
  end

  it 'changes the signature when the body changes' do
    expect(headers(body: 'one')['Authorization']).not_to eq(headers(body: 'two')['Authorization'])
  end
end
