# frozen_string_literal: true

require 'net/http'
require 'uri'

# Triggers Netlify's build hook so the static site rebuilds.
module NetlifyBuildHook
  TIMEOUT_SECONDS = 5

  module_function

  def trigger
    uri = URI.parse(ENV.fetch('NETLIFY_BUILD_HOOK_URL'))

    Net::HTTP.start(uri.host,
                    uri.port,
                    use_ssl: uri.scheme == 'https',
                    open_timeout: TIMEOUT_SECONDS,
                    read_timeout: TIMEOUT_SECONDS) do |http|
      http.post(uri.request_uri, '') # An empty POST is all the hook needs
    end
  end
end
