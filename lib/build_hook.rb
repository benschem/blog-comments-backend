# frozen_string_literal: true

require 'net/http'
require 'uri'

# Triggers the frontend host's build hook so the static site rebuilds
#
# Host-agnostic: any deploy/build hook is just a URL we POST an empty body to
# (Netlify, Vercel, Cloudflare Pages, a CI dispatch, etc). The URL is config
module BuildHook
  TIMEOUT_SECONDS = 5

  module_function

  def trigger(config: AppConfig.current)
    uri = URI.parse(config.build_hook_url)

    Net::HTTP.start(uri.host,
                    uri.port,
                    use_ssl: uri.scheme == 'https',
                    open_timeout: TIMEOUT_SECONDS,
                    read_timeout: TIMEOUT_SECONDS) do |http|
      http.post(uri.request_uri, '') # An empty POST is all the hook needs
    end
  end
end
