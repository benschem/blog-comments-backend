# frozen_string_literal: true

# Run standard Active Record commands like `rake db:migrate`
require 'sinatra/activerecord/rake'

# Internal prerequisite the AR db:* tasks expect; doubles as our app-boot hook
# (the require pulls in AR, the models, and lib/). Hidden from `rake -T`
namespace :db do
  task :load_config do # rubocop:disable Rake/Desc,Lint/RedundantCopDisableDirective
    require './app'
  end
end

# Command-line moderation
#
#   bundle exec rake comments:pending          # List comments awaiting moderation
#   bundle exec rake 'comments:approve[id]'    # Approve comment and trigger site rebuild
#   bundle exec rake 'comments:reject[id]'     # Reject comment
#   bundle exec rake 'comments:mark_spam[id]'  # Mark comment as spam
namespace :comments do
  desc 'List comments awaiting moderation'
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
    puts "  bundle exec rake 'comments:mark_spam[<id>]'"
  end

  desc 'Approve comment and trigger site rebuild'
  task :approve, [:id] => 'db:load_config' do |_task, args|
    comment = fetch_comment(args[:id])
    comment.approve!
    rebuild_outcome = attempt_site_rebuild
    puts "Approved: [##{comment.id}] (#{comment.post_slug} — #{comment.author_name}): #{rebuild_outcome}"
  end

  desc 'Reject comment'
  task :reject, [:id] => 'db:load_config' do |_task, args|
    comment = fetch_comment(args[:id])
    comment.reject!
    puts "Rejected: [##{comment.id}] (#{comment.post_slug} — #{comment.author_name})."
  end

  desc 'Mark comment as spam'
  task :mark_spam, [:id] => 'db:load_config' do |_task, args|
    comment = fetch_comment(args[:id])
    comment.mark_spam!
    puts "Marked as spam: [##{comment.id}] (#{comment.post_slug} — #{comment.author_name})."
  end
end

# Timestamps are stored in UTC. This will show AEST in winter, AEDT in summer.
def aest(time)
  time.in_time_zone('Australia/Sydney').strftime('%-d %b %Y, %-I:%M%p %Z')
end

def fetch_comment(id)
  abort "Usage: rake 'comments:approve[<id>]' — run comments:pending to see ids." if id.nil?

  Comment.find(id)
rescue ActiveRecord::RecordNotFound
  abort "No comment found with id #{id}."
end

def attempt_site_rebuild
  NetlifyBuildHook.trigger
  'site rebuild triggered'
rescue StandardError => e
  "site rebuild failed! (#{e.class}: #{e.message})"
end
