# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AppLogger do
  describe 'its line format' do
    # Pin the zone so %Z is deterministic regardless of where the suite runs
    around do |example|
      original = ENV.fetch('TZ', nil)
      ENV['TZ'] = 'Australia/Sydney'
      example.run
    ensure
      ENV['TZ'] = original
    end

    # Drive the formatter directly so we assert on the exact line without capturing
    # the global stdout the real logger is bound to.
    let(:line) { described_class.formatter.call('ERROR', Time.new(2026, 6, 13, 16, 50, 59), nil, '[AppMailer] boom') }

    it 'is a readable zoned timestamp, padded level, then the tagged message' do
      expect(line).to eq("Sat 13 Jun 16:50:59 AEST  ERROR  [AppMailer] boom\n")
    end
  end
end
