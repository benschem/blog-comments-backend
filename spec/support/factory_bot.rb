# frozen_string_literal: true

require 'factory_bot'

# Plain factory_bot (no factory_bot_rails autoloading), so point it at the
# factories directory explicitly and load the definitions once at boot
FactoryBot.definition_file_paths = [File.expand_path('../factories', __dir__)]
FactoryBot.find_definitions

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
end
