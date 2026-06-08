# frozen_string_literal: true

# Seed data for local development: a handful of comments across two posts in
# every moderation state, so you can exercise the full loop without hand-rolling
# rows — approved ones surface via GET /comments, pending ones via the moderation
# links printed at the end, and spam/rejected stay hidden.
#
# Run with `bundle exec rake db:seed`. Idempotent: it clears existing comments
# first, so re-running gives the same known set. Refuses to touch production.

if ENV['RACK_ENV'] == 'production'
  abort 'Refusing to seed in production (would wipe the comments table).'
end

Comment.delete_all

base_url = ENV.fetch('APP_BASE_URL', 'http://localhost:9292')

Comment.create!(
  [
    # --- hello-world: a lively thread ---
    {
      post_slug: 'hello-world', status: 'approved', created_at: 3.days.ago,
      author_name: 'Homer Simpson', author_website: 'https://homer.example',
      author_role: 'Nuclear Safety Inspector',
      body: 'Lovely write-up. The bit about bake-at-build rendering finally made it click for me.'
    },
    {
      post_slug: 'hello-world', status: 'approved', created_at: 1.day.ago,
      author_name: 'Marge Simpson', author_role: 'Homemaker',
      body: 'Agreed. Approve-first moderation is the right call for a personal blog.'
    },
    {
      post_slug: 'hello-world', status: 'pending', moderation_token: 'pending-hello',
      author_name: 'Lisa Simpson', author_website: 'https://lisa.example',
      body: 'Question: does the Netlify rebuild pick this up automatically once approved?'
    },
    {
      post_slug: 'hello-world', status: 'spam',
      author_name: 'Gil Gunderson', author_website: 'https://buy-cheap-pills.example',
      body: 'CHEAP WATCHES CLICK HERE!!!'
    },
    {
      post_slug: 'hello-world', status: 'rejected',
      author_name: 'Bart Simpson', body: 'first!!!1'
    },

    # --- getting-started: quieter, one of each visible state ---
    {
      post_slug: 'getting-started', status: 'approved', created_at: 2.hours.ago,
      author_name: 'Professor Frink', author_role: 'Research Scientist',
      body: 'Followed this end to end and it worked. Thanks for the detailed steps.'
    },
    {
      post_slug: 'getting-started', status: 'pending', moderation_token: 'pending-getting-started',
      author_name: 'Ned Flanders',
      body: 'Could you add a note about running the migrations in the test env too?'
    }
  ]
)

pending = Comment.where(status: 'pending').order(:created_at)

puts "Seeded #{Comment.count} blog post comments:"
puts "- #{Comment.where(status: 'approved').count} approved"
puts "- #{pending.count} pending"
puts "- #{Comment.where(status: 'spam').count} spam"
puts "- #{Comment.where(status: 'rejected').count} rejected"
puts
puts 'Moderation links for the pending comments:'
pending.each do |comment|
  puts "  #{comment.post_slug} — #{comment.author_name}"
  puts "    #{base_url}/moderate/#{comment.moderation_token}"
end
