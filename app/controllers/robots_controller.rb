# frozen_string_literal: true

# Serve a catch-all robots.txt that disallows crawling
class RobotsController < BaseController
  get '/robots.txt' do
    content_type 'text/plain'
    "User-agent: *\nDisallow: /\n"
  end
end
