# frozen_string_literal: true

# Run standard Active Record commands like `rake db:migrate`, `rake db:rollback`, and `rake db:seed`
require 'sinatra/activerecord/rake'

# Tell rake how to connect to the database for those commands
namespace :db do
  task :load_config do
    require './app'
  end
end
