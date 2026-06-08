# frozen_string_literal: true

# Run standard Active Record commands like `rake db:migrate`, `rake db:rollback`, and `rake db:seed`
require 'sinatra/activerecord/rake'

# Tell rake how to connect to the database for those commands
namespace :db do
  task :load_config do
    require './app'
  end
end

# Command-line moderation: with no admin dashboard, these are the fallback for
# triaging the queue. `comments:pending` lists the ids; approve/reject act on
# one by id (mirroring the web /moderate flow — approve also fires the rebuild).
namespace :comments do
  # Boot the app (AR connection, models, lib integrations) for the tasks below.
  task :boot do
    require './app'
  end

  desc 'List comments still awaiting moderation'
  task pending: :boot do
    queue = Comment.where(status: 'pending').order(:created_at)

    if queue.empty?
      puts 'No comments awaiting moderation.'
      next
    end

    puts "#{queue.size} comment(s) awaiting moderation:\n\n"
    queue.each do |comment|
      puts "##{comment.id}  [#{aest(comment.created_at)}]  " \
           "#{comment.post_slug} — #{comment.author_name}"
      puts "      #{comment.body.truncate(100)}"
    end

    puts "\nModerate one by id (quote the brackets so the shell doesn't glob them):"
    puts "  bundle exec rake 'comments:approve[<id>]'"
    puts "  bundle exec rake 'comments:reject[<id>]'"
  end

  desc 'Approve a comment by id and trigger a site rebuild'
  task :approve, [:id] => :boot do |_task, args|
    comment = fetch_comment(args[:id])
    comment.approve!

    begin
      NetlifyBuildTrigger.fire
      outcome = 'site rebuild triggered'
    rescue StandardError => e
      outcome = "approved, but the build hook failed (#{e.class}: #{e.message})"
    end

    puts "Approved ##{comment.id} (#{comment.post_slug} — #{comment.author_name}): #{outcome}"
  end

  desc 'Reject a comment by id'
  task :reject, [:id] => :boot do |_task, args|
    comment = fetch_comment(args[:id])
    comment.reject!
    puts "Rejected ##{comment.id} (#{comment.post_slug} — #{comment.author_name})."
  end
end

# Render a stored (UTC) timestamp in Australian Eastern time, so the queue reads
# in local time. DST-aware: shows AEST in winter, AEDT in summer.
def aest(time)
  time.in_time_zone('Australia/Sydney').strftime('%-d %b %Y, %-I:%M%p %Z')
end

# Look up the comment a moderation task should act on, aborting with a helpful
# message when the id is missing or unknown.
def fetch_comment(id)
  abort "Usage: rake 'comments:approve[<id>]' — run comments:pending to see ids." if id.nil?

  Comment.find(id)
rescue ActiveRecord::RecordNotFound
  abort "No comment found with id #{id}."
end
