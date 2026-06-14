# frozen_string_literal: true

# Start coverage before app code loads so every line is counted and exclude the specs themselves
require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  add_filter 'config/puma.rb'

  # Track both line and branch coverage so a conditional with only one side tested
  # (e.g. an `if` whose `else` never runs) shows up instead of passing as "covered"
  enable_coverage :branch

  # Surface runtime files that no spec requires as 0% instead of omitting them
  track_files '{app,lib,mailer,config}/**/*.rb'

  # Fail the run if coverage regresses
  minimum_coverage line: 100, branch: 88
end

# Use the `test` block from config/database.yml to load the test db file before the app boots
ENV['RACK_ENV'] = 'test'

# Boot the Sinatra app and ActiveRecord connection once for the whole test suite
require_relative '../app'

# Load support files (factory_bot, database_cleaner, rack-test helpers, etc.)
Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |file| require file }

RSpec.configure do |config|
  # Include `chain` helper text in custom-matcher descriptions and failure messages
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # Stub/mock only methods that actually exist, so doubles can't drift from the real API
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  # Shared-context metadata applies to host groups only (no implicit auto-inclusion) (RSpec 4 default)
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # `fit`/`fdescribe` runs just the focused examples, but only when something is focused
  config.filter_run_when_matching :focus

  # Record pass/fail per example so `--only-failures` and `--next-failure` work
  config.example_status_persistence_file_path = 'spec/examples.txt'

  # No monkey-patched `should`` - use the `expect` syntax
  config.disable_monkey_patching!

  # Randomise example order to surface hidden ordering dependencies between specs
  config.order = :random

  # Seed that randomisation from `config.seed` so a failing run is reproducible with `--seed`
  Kernel.srand config.seed
end
