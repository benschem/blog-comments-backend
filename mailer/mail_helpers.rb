# frozen_string_literal: true

require 'cgi'

# Helpers common across all emails
module MailHelpers
  module_function

  def escape_html(text)
    CGI.escapeHTML(text.to_s)
  end
end
