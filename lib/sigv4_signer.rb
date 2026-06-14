# frozen_string_literal: true

require 'openssl'
require 'digest'

# Signs a single HTTP request with AWS Signature Version 4 ("SigV4").
#
# Despite the "AWS" name, nothing here talks to Amazon. SigV4 is the authentication scheme
# the S3 API requires, and Cloudflare R2 implements the S3 API - so to upload to R2 we sign
# exactly as an S3 client would (MinIO, Backblaze B2, DigitalOcean Spaces all work the same
# way). The output is just an `Authorization` header string; the storage endpoint recomputes
# the same signature from the shared secret and checks that it matches.
#
# The recipe is four steps, always run in this order (AWS docs: "Signature Version 4"):
#
#   1. Canonical request - a byte-exact, normalised description of the request.
#   2. String to sign    - algorithm + timestamp + scope + hash(canonical request).
#   3. Signing key       - the secret, HMAC-chained through date -> region -> service.
#   4. Signature         - HMAC(signing key, string to sign); drop it into the header.
#
# `#headers` returns the headers to attach to the outgoing request. `#authorization` below
# is the whole recipe in one place; read it first, then the helpers it calls.
class Sigv4Signer
  ALGORITHM = 'AWS4-HMAC-SHA256'
  REGION = 'auto' # R2 has no regions; SigV4 still needs a value and 'auto' is R2's convention
  SERVICE = 's3'
  SIGNED_HEADERS = 'host;x-amz-content-sha256;x-amz-date' # the headers covered by the signature

  def initialize(config:, http_method:, uri:, body:, now:)
    @config = config
    @http_method = http_method
    @uri = uri
    @body = body
    @now = now
  end

  # The headers that authenticate the request - attach all four to the outgoing request.
  def headers
    {
      'Host' => @uri.host,
      'X-Amz-Date' => amz_date,
      'X-Amz-Content-Sha256' => payload_hash,
      'Authorization' => authorization
    }
  end

  private

  # The four SigV4 steps, in order. Each `# n.` lines up with the recipe in the class comment.
  def authorization
    canonical_request = build_canonical_request                  # 1.
    string_to_sign    = build_string_to_sign(canonical_request)  # 2.
    signing_key       = derive_signing_key                       # 3.
    signature         = hex_hmac(signing_key, string_to_sign)    # 4.

    "#{ALGORITHM} Credential=#{@config.r2_access_key_id}/#{credential_scope}, " \
      "SignedHeaders=#{SIGNED_HEADERS}, Signature=#{signature}"
  end

  def hex_hmac(key, data) = OpenSSL::HMAC.hexdigest('sha256', key, data)

  # Step 1: a normalised description of the request. The server reproduces this exact string
  # to re-sign, so the format (sorted lowercase headers, hashed body) is load-bearing.
  def build_canonical_request
    [
      @http_method,        # e.g. PUT
      @uri.path,           # /bucket/key - our keys are URL-safe, so no percent-encoding
      '',                  # query string (none)
      canonical_headers,   # one "name:value\n" per signed header, sorted, lowercase
      SIGNED_HEADERS,      # which headers we signed
      payload_hash         # hex SHA256 of the body
    ].join("\n")
  end

  def canonical_headers
    "host:#{@uri.host}\n" \
      "x-amz-content-sha256:#{payload_hash}\n" \
      "x-amz-date:#{amz_date}\n"
  end

  def payload_hash = @payload_hash ||= Digest::SHA256.hexdigest(@body)

  # Step 2: wrap the canonical request with the algorithm, timestamp, and credential scope.
  def build_string_to_sign(canonical_request)
    [
      ALGORITHM,
      amz_date,
      credential_scope,
      Digest::SHA256.hexdigest(canonical_request)
    ].join("\n")
  end

  def credential_scope = "#{date_stamp}/#{REGION}/#{SERVICE}/aws4_request"

  # Step 3: HMAC-chain the secret through date -> region -> service, so a captured signature
  # can't be replayed on another day, region, or service.
  def derive_signing_key
    key = hmac("AWS4#{@config.r2_secret_access_key}", date_stamp)
    key = hmac(key, REGION)
    key = hmac(key, SERVICE)
    hmac(key, 'aws4_request')
  end

  def hmac(key, data) = OpenSSL::HMAC.digest('sha256', key, data)

  # amz_date -> "20260614T033000Z" (full instant)
  def amz_date = @amz_date ||= @now.strftime('%Y%m%dT%H%M%SZ')
  # date_stamp -> "20260614" (day only)
  def date_stamp = @date_stamp ||= @now.strftime('%Y%m%d')
end
