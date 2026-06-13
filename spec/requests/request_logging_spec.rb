# frozen_string_literal: true

require 'spec_helper'

# Rack::CommonLogger writes its access line via `logger << msg` (a stdlib Logger
# routes `<<` straight to the device), so spy on `<<` to assert what gets logged.
RSpec.describe 'Request logging', type: :request do
  before { allow(AppLogger).to receive(:<<) }

  it 'writes an access line for ordinary traffic' do
    get '/comments', post_slug: 'hello-world'
    expect(AppLogger).to have_received(:<<).with(%r{GET /comments})
  end

  it 'skips the health-check probe, which halts above CommonLogger' do
    get '/up'
    expect(AppLogger).not_to have_received(:<<)
  end
end
