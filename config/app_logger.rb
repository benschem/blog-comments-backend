# frozen_string_literal: true

require 'logger'

# One process-wide logger so the plain-Ruby jobs, mailer, and lib objects
# (which can't reach Sinatra's logger) all write to the same place: stdout
AppLogger = Logger.new($stdout)

# Set the logger to emit readable, timestamped, tagged logs
AppLogger.formatter = proc do |severity, time, _progname, message|
  request_id = Thread.current[RequestId::THREAD_KEY]
  timestamp = time.strftime('%a %d %b %H:%M:%S %Z')

  # Thu 18 Jun 23:38:13 AEST  INFO   [a1b2c3d4e5f6a7b8]  [POST /comments] honeypot tripped from 1.2.3.4
  fields = [timestamp, severity.ljust(5), ("[#{request_id}]" if request_id), message]
  "#{fields.compact.join('  ')}\n"
end
