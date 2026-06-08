# frozen_string_literal: true

require 'net/http'
require 'uri'

# Fires Netlify's build hook so the static site rebuilds and bakes in the
# freshly-approved comment. An empty POST is all the hook needs. Kept dependency
# free (stdlib net/http) and deliberately decoupled from the model: callers
# invoke it *after* `approve!` has persisted and rescue any failure, so a flaky
# deploy hook can never roll back an approval. Reads ENV at call-time.
module NetlifyBuildTrigger
  # Short timeouts: the hook is fire-and-forget, never block the request on it.
  TIMEOUT_SECONDS = 5

  module_function

  def fire
    uri = URI.parse(ENV.fetch('NETLIFY_BUILD_HOOK_URL'))
    Net::HTTP.start(uri.host, uri.port,
                    use_ssl: uri.scheme == 'https',
                    open_timeout: TIMEOUT_SECONDS,
                    read_timeout: TIMEOUT_SECONDS) do |http|
      http.post(uri.request_uri, '')
    end
  end
end
