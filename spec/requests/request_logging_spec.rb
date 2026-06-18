# frozen_string_literal: true

require 'spec_helper'

# RequestLogger emits the access line through AppLogger.info/warn/error (status
# dependent), so spy on those to assert what gets logged.
RSpec.describe 'Request logging', type: :request do
  it 'writes an access line for ordinary traffic' do
    allow(AppLogger).to receive(:info)
    get '/comments', post_slug: 'hello-world'
    expect(AppLogger).to have_received(:info).with(%r{\[GET /comments})
  end

  it 'skips the health-check probe, which halts above RequestLogger' do
    allow(AppLogger).to receive(:info)
    get '/up'
    expect(AppLogger).not_to have_received(:info)
  end

  it 'tags the access line with the request ID end to end' do
    output = capturing_app_log { get '/comments', post_slug: 'hello-world' }
    expect(output).to match(%r{\[[0-9a-f]{16}\]  \[GET /comments})
  end

  # Point AppLogger at a buffer for the duration of the block and return what it wrote.
  def capturing_app_log
    io = StringIO.new
    AppLogger.reopen(io)
    yield
    io.string
  ensure
    AppLogger.reopen(File::NULL)
  end
end
