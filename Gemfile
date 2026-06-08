# frozen_string_literal: true

source 'https://rubygems.org'

# Single source of truth for the Ruby version: read .ruby-version so Bundler,
# rbenv, and the Dockerfile all agree on the same number.
ruby file: '.ruby-version'

gem 'puma'
gem 'rack-attack'
gem 'rackup'
gem 'rake'
gem 'resend'
gem 'sinatra'
gem 'sinatra-activerecord'
gem 'sqlite3'

group :development, :test do
  gem 'dotenv'
  gem 'rack-test'
  gem 'rspec'

  gem 'simplecov', '~> 0.22.0', require: false

  gem 'database_cleaner-active_record'
  gem 'factory_bot'
  gem 'faker', '~> 3.8'

  gem 'awesome_print'
  gem 'debug', platforms: %i[mri]

  gem 'rubocop', '~> 1.87', require: false
  gem 'rubocop-factory_bot', '~> 2.28', require: false
  gem 'rubocop-performance', '~> 1.26', require: false
  gem 'rubocop-rake', '~> 0.7', require: false
  gem 'rubocop-rspec', '~> 3.10', require: false
end
