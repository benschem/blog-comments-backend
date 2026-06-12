# frozen_string_literal: true

# Run standard Active Record commands like `rake db:migrate`
require 'sinatra/activerecord/rake'

# Internal prerequisite the AR db:* tasks expect; doubles as our app-boot hook
# (the require pulls in AR, the models, and lib/). Hidden from `rake -T` on
# purpose, so it carries no desc and opts out of Rake/Desc.
namespace :db do
  task :load_config do # rubocop:disable Rake/Desc,Lint/RedundantCopDisableDirective
    require './app'
  end
end

# Command-line moderation: with no admin dashboard, these are the fallback for
# triaging the queue. `comments:pending` lists the ids; approve/reject act on
# one by id (mirroring the web /moderate flow — approve also fires the rebuild).
namespace :comments do
  desc 'List comments still awaiting moderation'
  task pending: 'db:load_config' do
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
  task :approve, [:id] => 'db:load_config' do |_task, args|
    comment = fetch_comment(args[:id])
    comment.approve!

    begin
      NetlifyBuildHook.trigger
      outcome = 'site rebuild triggered'
    rescue StandardError => e
      outcome = "approved, but the build hook failed (#{e.class}: #{e.message})"
    end

    puts "Approved ##{comment.id} (#{comment.post_slug} — #{comment.author_name}): #{outcome}"
  end

  desc 'Reject a comment by id'
  task :reject, [:id] => 'db:load_config' do |_task, args|
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
