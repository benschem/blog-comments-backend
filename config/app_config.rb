# frozen_string_literal: true

# Process wide, immutable value object holding the env values the app needs
class AppConfig
  ATTR_ENV_MAP = {
    app_base_url: 'APP_BASE_URL',
    resend_api_key: 'RESEND_API_KEY',
    resend_from_email: 'RESEND_FROM_EMAIL',
    moderation_notify_email: 'MODERATION_NOTIFY_EMAIL',
    build_hook_url: 'BUILD_HOOK_URL'
  }.freeze

  class MissingEnvError < StandardError; end

  attr_reader :app_base_url, :resend_api_key, :resend_from_email,
              :moderation_notify_email, :build_hook_url

  def initialize(app_base_url:, resend_api_key:, resend_from_email:,
                 moderation_notify_email:, build_hook_url:)
    @app_base_url = app_base_url
    @resend_api_key = resend_api_key
    @resend_from_email = resend_from_email
    @moderation_notify_email = moderation_notify_email
    @build_hook_url = build_hook_url
    freeze
  end

  class << self
    # Built lazily so rake tasks that never touch config can boot without it
    def current
      @current ||= build
    end

    # Lets the test suite install a dummy config without touching ENV
    attr_writer :current

    def build(env = ENV)
      attributes = ATTR_ENV_MAP.transform_values { |key_name| env[key_name].to_s.strip }
      missing = ATTR_ENV_MAP.select { |attr, _env_key| attributes[attr].blank? }.values
      raise MissingEnvError, "Missing required config: #{missing.join(', ')}" if missing.any?

      new(**attributes)
    end
  end
end
