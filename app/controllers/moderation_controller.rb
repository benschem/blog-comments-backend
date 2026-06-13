# frozen_string_literal: true

# Moderation endpoints
class ModerationController < BaseController
  MODERATION_ROUTES = [
    '/moderate/:token',
    '/moderate/:token/approve',
    '/moderate/:token/reject'
  ].freeze

  helpers do
    def escape_html(text)
      Rack::Utils.escape_html(text.to_s)
    end

    def rebuild_static_site
      NetlifyBuildHook.trigger
    rescue StandardError => e
      warn "[POST /moderate approve] Build hook failed for ##{@comment.id}: #{e.class}: #{e.message}"
    end
  end

  MODERATION_ROUTES.each do |route|
    before(route) do
      @comment = Comment.find_by(moderation_token: params[:token]) || halt(404)
    end
  end

  # We can't approve or reject comments directly from the moderation email body
  # because email clients often prefetch links, meaning they could accidently
  # approve/reject comments. Instead, render a confirmation page with forms.
  get '/moderate/:token' do
    erb :moderate
  end

  post '/moderate/:token/approve' do
    @comment.approve!
    rebuild_static_site
    redirect to("/moderate/#{@comment.moderation_token}")
  end

  post '/moderate/:token/reject' do
    @comment.reject!
    redirect to("/moderate/#{@comment.moderation_token}")
  end
end
