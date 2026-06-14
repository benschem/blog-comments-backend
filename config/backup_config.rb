# frozen_string_literal: true

# Process-wide, immutable value object holding the R2 credentials the backup needs
#
# Kept separate from AppConfig on purpose: serving comments must not depend on backup
# credentials. AppConfig is memoized at web boot (config.ru) so missing web-critical ENV
# crashes the server immediately; folding R2 keys in there would both break dev/test boot
# and wrongly couple "can we serve comments" to "are backup creds present". So this is built
# lazily instead - it only fails fast when a backup actually runs.
class BackupConfig
  ATTR_ENV_MAP = {
    r2_access_key_id: 'R2_ACCESS_KEY_ID',
    r2_secret_access_key: 'R2_SECRET_ACCESS_KEY',
    r2_endpoint: 'R2_ENDPOINT'
  }.freeze

  class MissingEnvError < StandardError; end

  attr_reader :r2_access_key_id, :r2_secret_access_key, :r2_endpoint

  def initialize(r2_access_key_id:, r2_secret_access_key:, r2_endpoint:)
    @r2_access_key_id = r2_access_key_id
    @r2_secret_access_key = r2_secret_access_key
    @r2_endpoint = r2_endpoint
    freeze
  end

  class << self
    # Built lazily so the web app and rake tasks that never back up boot without R2 config
    def current
      @current ||= build
    end

    # Lets the test suite install a dummy config without touching ENV
    attr_writer :current

    def build(env = ENV)
      attributes = ATTR_ENV_MAP.transform_values { |key_name| env[key_name].to_s.strip }
      missing = ATTR_ENV_MAP.select { |attr, _env_key| attributes[attr].blank? }.values
      raise MissingEnvError, "Missing required backup config: #{missing.join(', ')}" if missing.any?

      new(**attributes)
    end
  end
end
