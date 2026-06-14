# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BackupFailureEmail do
  let(:config) { build_config_for_specs }

  # Capture the envelope handed to the transport instead of sending for real
  # (the trailing `**` swallows the config keyword the deliver_* methods pass on).
  let(:email) { {} }

  before { allow(AppMailer).to receive(:deliver) { |params, **| email.merge!(params) } }

  describe '.deliver_for' do
    let(:error) { R2Uploader::UploadError.new('PutObject backup.gz returned 403: AccessDenied') }

    before { described_class.deliver_for(error, config:) }

    it 'addresses the moderation inbox from the configured sender' do
      expect(email).to include(from: config.resend_from_email, to: config.moderation_notify_email)
    end

    it 'uses a subject that flags the failure' do
      expect(email[:subject]).to match(/backup failed/i)
    end

    it 'names the error class and message in the body', :aggregate_failures do
      expect(email[:html]).to include(error.class.name)
      expect(email[:html]).to include(error.message)
    end
  end

  context 'with HTML in the error message' do
    let(:error) { StandardError.new('<script>alert(1)</script>') }

    before { described_class.deliver_for(error, config:) }

    it 'escapes the error message', :aggregate_failures do
      expect(email[:html]).to include(MailHelpers.escape_html(error.message))
      expect(email[:html]).not_to include(error.message)
    end
  end
end
