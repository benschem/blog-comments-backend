# frozen_string_literal: true

require 'logger'

# One process-wide logger so the plain-Ruby jobs, mailer, and lib objects
# (which can't reach Sinatra's logger) all write to the same place: stdout
AppLogger = Logger.new($stdout)

# Readable local-time lines for eyeballing in `docker logs`, with the zone spelled
# out (%Z) since the line isn't UTC — e.g. "Sat 13 Jun 16:50:59 AEST  ERROR  ...".
# The zone comes from the process's TZ (set TZ=Australia/Sydney in the container so
# it isn't the slim image's UTC default); %Z then tracks the AEST/AEDT DST switch.
AppLogger.formatter = proc do |severity, time, _progname, message|
  "#{time.strftime('%a %d %b %H:%M:%S %Z')}  #{severity.ljust(5)}  #{message}\n"
end
