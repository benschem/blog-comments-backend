# frozen_string_literal: true

# A dummy set of config values and a way to set them for specs
module ConfigHelpers
  DEFAULTS = {
    'APP_BASE_URL' => 'https://comments.benschem.dev',
    'RESEND_API_KEY' => 'test_key',
    'RESEND_FROM_EMAIL' => 'comments@benschem.dev',
    'MODERATION_NOTIFY_EMAIL' => 'ben@benschem.dev',
    'NETLIFY_BUILD_HOOK_URL' => 'https://api.netlify.com/build_hooks/abc123'
  }.freeze

  # Build config the way production does, optionally overriding individual values
  def build_config_for_specs(overrides = {})
    AppConfig.build(ConfigHelpers::DEFAULTS.merge(overrides))
  end
end

RSpec.configure do |config|
  config.include ConfigHelpers

  # Reset AppConfig.current to default before each example
  config.before { AppConfig.current = build_config_for_specs }
end
