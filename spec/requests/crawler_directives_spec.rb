# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Crawler directives', type: :request do
  describe 'GET /robots.txt' do
    before { get '/robots.txt' }

    it 'responds 200' do
      expect(last_response).to be_ok
    end

    it 'is served as plain text' do
      expect(last_response.content_type).to include('text/plain')
    end

    it 'disallows all crawlers' do
      expect(last_response.body).to eq("User-agent: *\nDisallow: /\n")
    end
  end

  describe 'X-Robots-Tag header' do
    it 'marks the public JSON read endpoint noindex' do
      get '/comments', post_slug: 'anything'
      expect(last_response.headers['X-Robots-Tag']).to eq('noindex')
    end

    it 'marks the health endpoint noindex' do
      get '/up'
      expect(last_response.headers['X-Robots-Tag']).to eq('noindex')
    end

    it 'marks robots.txt itself noindex' do
      get '/robots.txt'
      expect(last_response.headers['X-Robots-Tag']).to eq('noindex')
    end
  end
end
