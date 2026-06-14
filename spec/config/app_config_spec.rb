# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AppConfig do
  let(:complete) do
    {
      'APP_BASE_URL' => 'https://example.test',
      'RESEND_API_KEY' => 're_xxx',
      'RESEND_FROM_EMAIL' => 'from@example.test',
      'MODERATION_NOTIFY_EMAIL' => 'mod@example.test',
      'BUILD_HOOK_URL' => 'https://hooks.test/abc'
    }
  end

  describe '.build' do
    let(:config) { described_class.build(complete.merge('RESEND_FROM_EMAIL' => '  hi@example.test  ')) }

    it 'reads and strips the value for each attribute' do
      expect(config.resend_from_email).to eq('hi@example.test')
    end

    it 'raises and names every missing key' do
      expect { described_class.build(complete.except('RESEND_API_KEY', 'BUILD_HOOK_URL')) }
        .to raise_error(AppConfig::MissingEnvError, /RESEND_API_KEY.*BUILD_HOOK_URL/)
    end

    it 'treats blank or whitespace-only values as missing' do
      expect { described_class.build(complete.merge('APP_BASE_URL' => '   ')) }
        .to raise_error(AppConfig::MissingEnvError, /APP_BASE_URL/)
    end
  end

  describe '.current' do
    it 'builds once and memoizes the result' do
      described_class.current = nil
      allow(described_class).to receive(:build).and_return(build_config_for_specs)

      2.times { described_class.current }

      expect(described_class).to have_received(:build).once
    end
  end
end
