# frozen_string_literal: true

# Run standard Active Record commands like `rake db:migrate`, `rake db:rollback`, and `rake db:seed`
require 'sinatra/activerecord/rake'

# Tell rake how to connect to the database for those commands
namespace :db do
  task :load_config do
    require './app'
  end
end

namespace :comments do
  desc 'List comments still awaiting moderation'
  task :pending do
    require './app'
    pending = Comment.where(status: 'pending').order(:created_at)

    if pending.empty?
      puts 'No comments awaiting moderation.'
      next
    end

    base = ENV.fetch('APP_BASE_URL', '')
    puts "#{pending.size} comment(s) awaiting moderation:\n\n"
    pending.each do |comment|
      puts "- [#{comment.created_at}] #{comment.post_slug} — #{comment.author_name}"
      puts "    #{comment.body.truncate(100)}"
      puts "    moderate: #{base}/moderate/#{comment.moderation_token}"
    end
  end
end
