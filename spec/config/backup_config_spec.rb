# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BackupConfig do
  let(:complete) do
    {
      'R2_ACCESS_KEY_ID' => 'access-key-id',
      'R2_SECRET_ACCESS_KEY' => 'secret-access-key',
      'R2_ENDPOINT' => 'https://acct.r2.cloudflarestorage.com'
    }
  end

  describe '.build' do
    it 'reads and strips the value for each attribute' do
      config = described_class.build(complete.merge('R2_ENDPOINT' => '  https://acct.r2.cloudflarestorage.com  '))
      expect(config.r2_endpoint).to eq('https://acct.r2.cloudflarestorage.com')
    end

    it 'raises and names every missing key' do
      expect { described_class.build(complete.except('R2_ACCESS_KEY_ID', 'R2_ENDPOINT')) }
        .to raise_error(BackupConfig::MissingEnvError, /R2_ACCESS_KEY_ID.*R2_ENDPOINT/)
    end

    it 'treats blank or whitespace-only values as missing' do
      expect { described_class.build(complete.merge('R2_SECRET_ACCESS_KEY' => '   ')) }
        .to raise_error(BackupConfig::MissingEnvError, /R2_SECRET_ACCESS_KEY/)
    end
  end

  describe '.current' do
    it 'builds once and memoizes the result' do
      described_class.current = nil
      allow(described_class).to receive(:build).and_return(described_class.build(complete))

      2.times { described_class.current }

      expect(described_class).to have_received(:build).once
    end
  end
end
