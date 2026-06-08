# frozen_string_literal: true

require 'database_cleaner/active_record'

RSpec.configure do |config|
  # Rails automatically wraps every test in a transaction but Sinatra doesn't
  # This mimics Rails by ensuring a clean, isolated database state
  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation) # Wipes database once up front
  end

  config.before do
    DatabaseCleaner.strategy = :transaction # Fastest strategy for rack-test
  end

  # Wraps each example block inside a database transaction and rolls it back
  config.around do |example|
    DatabaseCleaner.cleaning { example.run }
  end
end
