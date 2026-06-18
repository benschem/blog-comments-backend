# frozen_string_literal: true

# Access logger that writes one tagged access line per request, right after the
# response is built. The line flows through AppLogger like every other log.
#
# Logging synchronously (not at body-close) keeps the request still on the
# stack, so RequestId's thread-local is live and the formatter tags it for us.
class RequestLogger
  def initialize(app)
    @app = app
  end

  def call(env)
    started_at = monotonic_time
    status, headers, body = @app.call(env)
    duration_ms = monotonic_time - started_at

    request = Rack::Request.new(env)
    AppLogger.public_send(severity_for(status), access_line(request, status, headers, duration_ms))

    [status, headers, body]
  end

  private

  def access_line(request, status, headers, duration_ms)
    method = request.request_method
    path = sanitise(request.fullpath)
    size = headers['content-length'] || '-' # '-' when the response has no body (HEAD/204/streaming)

    "[#{method} #{path}] #{status} #{size}B (#{duration_ms.round(1)}ms) from #{request.ip}"
  end

  def severity_for(status)
    return :error if status >= 500
    return :warn if status >= 400

    :info
  end

  # A steadily-increasing clock, in milliseconds. Unlike Time.now it never jumps
  # (NTP corrections, DST), so subtracting two readings gives a true elapsed time.
  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
  end

  # Swap any non-printable character (newlines, escape codes) for '?' so a crafted
  # path can't inject extra lines or terminal codes into the log.
  def sanitise(path)
    path.gsub(/[^[:print:]]/, '?')
  end
end
