# frozen_string_literal: true

require 'net/http'
require 'uri'

# Uploads a single object to the R2 bucket with an S3 PutObject, retrying transient failures.
# Stdlib only (Net::HTTP), matching NetlifyBuildHook's no-gem style. The request is signed by
# Sigv4Signer - this class is only concerned with the HTTP call and its failure handling.
#
# Object keys must be URL-safe (the timestamped `comments-<...>.sqlite3.gz` keys are), since
# the signed canonical request uses the path verbatim without percent-encoding.
class R2Uploader
  BUCKET = 'blog-comments-backups'

  OPEN_TIMEOUT_SECONDS = 5
  READ_TIMEOUT_SECONDS = 30 # the upload body can take longer than a hook ping
  UPLOAD_MAX_ATTEMPTS = 3
  BACKOFF_BASE_SECONDS = 1 # 1s then 2s between the (few) retries

  # Network-level failures worth retrying; 4xx (e.g. a bad token) is deliberately not here
  RETRYABLE_NETWORK_ERRORS = [
    SocketError, IOError, Errno::ECONNRESET, Errno::ECONNREFUSED,
    Errno::EHOSTUNREACH, Net::OpenTimeout, Net::ReadTimeout
  ].freeze

  class UploadError < StandardError; end

  # Retryable: a 5xx or a network blip
  class TransientUploadError < UploadError; end

  def self.put(key:, body:, content_type:, config: BackupConfig.current, now: Time.now.utc)
    new(key:, body:, content_type:, config:, now:).put
  end

  def initialize(key:, body:, content_type:, config:, now:)
    @key = key
    @body = body
    @content_type = content_type
    @config = config
    @now = now
  end

  def put
    attempt = 0
    begin
      attempt += 1
      upload
    rescue TransientUploadError => e
      raise if attempt >= UPLOAD_MAX_ATTEMPTS

      AppLogger.warn "[R2Uploader] attempt #{attempt}/#{UPLOAD_MAX_ATTEMPTS} failed (#{e.message}); retrying"
      sleep BACKOFF_BASE_SECONDS * (2**(attempt - 1))
      retry
    end
  end

  private

  def upload
    response = Net::HTTP.start(uri.host, uri.port, **connection_options) do |http|
      http.request(signed_request)
    end
    check!(response)
  rescue *RETRYABLE_NETWORK_ERRORS => e
    raise TransientUploadError, "#{e.class}: #{e.message}"
  end

  def connection_options
    { use_ssl: uri.scheme == 'https', open_timeout: OPEN_TIMEOUT_SECONDS, read_timeout: READ_TIMEOUT_SECONDS }
  end

  def check!(response)
    code = response.code.to_i
    return if code.between?(200, 299)
    raise TransientUploadError, "PutObject #{@key} returned #{response.code}" if code >= 500

    raise UploadError, "PutObject #{@key} returned #{response.code}: #{response.body}"
  end

  def uri = @uri ||= URI.parse("#{@config.r2_endpoint}/#{BUCKET}/#{@key}")

  def signed_request
    request = Net::HTTP::Put.new(uri)
    signer.headers.each { |name, value| request[name] = value }
    request['Content-Type'] = @content_type
    request.body = @body
    request
  end

  def signer
    Sigv4Signer.new(config: @config, http_method: 'PUT', uri:, body: @body, now: @now)
  end
end
