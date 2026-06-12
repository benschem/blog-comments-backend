# frozen_string_literal: true

# Moderation endpoints, reached only via the unguessable token in the link
# emailed to the moderator — there is no dashboard or login, the token *is* the
# capability. GET renders a confirmation page and is deliberately
# side-effect-free so an email client prefetching the link can't auto-approve;
# the state change happens only on the POSTs.
class ModerationController < BaseController
  # Inline review page. Kept tiny and noindex; every user-controlled field is
  # HTML-escaped via the `escape_html` helper since the body is free text.
  MODERATION_PAGE = <<~ERB
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <meta name="robots" content="noindex">
      <title>Moderate comment</title>
    </head>
    <body>
      <h1>Comment on <%= escape_html @comment.post_slug %></h1>
      <p>
        <strong><%= escape_html @comment.author_name %></strong>
        <% if @comment.author_role.present? %>&mdash; <%= escape_html @comment.author_role %><% end %>
        <% if @comment.author_website.present? %>(<%= escape_html @comment.author_website %>)<% end %>
      </p>
      <blockquote><%= escape_html @comment.body %></blockquote>
      <p>Current status: <strong><%= escape_html @comment.status %></strong></p>
      <form method="post" action="/moderate/<%= @comment.moderation_token %>/approve" style="display:inline">
        <button type="submit">Approve</button>
      </form>
      <form method="post" action="/moderate/<%= @comment.moderation_token %>/reject" style="display:inline">
        <button type="submit">Reject</button>
      </form>
    </body>
    </html>
  ERB

  helpers do
    def comment_for_moderation
      Comment.find_by(moderation_token: params[:token]) || halt(404)
    end

    def escape_html(text)
      Rack::Utils.escape_html(text.to_s)
    end

    def rebuild_static_site
      NetlifyBuildHook.trigger
    end
  end

  get '/moderate/:token' do
    @comment = comment_for_moderation
    erb MODERATION_PAGE
  end

  post '/moderate/:token/approve' do
    comment = comment_for_moderation
    comment.approve!

    begin
      rebuild_static_site
    rescue StandardError => e
      warn "[POST /moderate approve] build hook failed for ##{comment.id}: #{e.class}: #{e.message}"
    end

    'Approved. The site will rebuild shortly.'
  end

  post '/moderate/:token/reject' do
    comment = comment_for_moderation
    comment.reject! # No rebuild
    'Rejected.'
  end
end
