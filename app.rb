# frozen_string_literal: true

require 'bundler/setup'
Bundler.require(:default, ENV['RACK_ENV'] || :development)

require 'dotenv/load'
require 'sinatra'
require 'sinatra/activerecord'

set :database_file, 'config/database.yml'

post '/' do
  # Deal with comment submissions
end
