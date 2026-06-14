# frozen_string_literal: true

require 'sqlite3'
require 'zlib'
require 'stringio'
require 'tmpdir'

# Backs up the SQLite database to R2: snapshot -> integrity check -> gzip -> upload
#
# Runs in-process on a schedule (config/scheduler.rb) and by hand (rake comments:backup)
# Any failure is logged, emailed to the moderator (BackupFailureEmail), and re-raised
module SqliteBackup
  CONTENT_TYPE = 'application/gzip'

  class IntegrityError < StandardError; end

  module_function

  def run(config: BackupConfig.current)
    key, bytes = perform(config)
    AppLogger.info "[SqliteBackup] uploaded #{key} (#{bytes} bytes)"
  rescue StandardError => e
    AppLogger.error "[SqliteBackup] backup failed: #{e.class}: #{e.message}"
    notify_failure(e)
    raise
  end

  def perform(config)
    Dir.mktmpdir('comments-backup') do |dir|
      snapshot = File.join(dir, 'snapshot.sqlite3')
      take_snapshot(snapshot)
      verify_integrity(snapshot)
      body = gzip(File.binread(snapshot))
      key = object_key
      R2Uploader.put(key:, body:, content_type: CONTENT_TYPE, config:)
      [key, body.bytesize]
    end
  end

  # The snapshot uses `VACUUM INTO` over its own short-lived connection (not the live
  # ActiveRecord one): it's WAL-safe, captures only committed rows, and folds the -wal sidecar
  # into one standalone file - so a future restore is a single file, no loose -wal/-shm.
  def take_snapshot(snapshot)
    SQLite3::Database.new(database_path) { |db| db.execute("VACUUM INTO '#{snapshot}'") }
  end

  def verify_integrity(snapshot)
    return if integrity_ok?(snapshot)

    raise IntegrityError, 'snapshot failed its PRAGMA integrity_check'
  end

  def integrity_ok?(snapshot)
    result = nil
    SQLite3::Database.new(snapshot) { |db| result = db.execute('PRAGMA integrity_check') }
    result == [['ok']]
  end

  def gzip(data)
    buffer = StringIO.new
    writer = Zlib::GzipWriter.new(buffer)
    writer.write(data)
    writer.close
    buffer.string
  end

  def notify_failure(error)
    BackupFailureEmail.deliver_for(error)
  rescue StandardError => e
    AppLogger.error "[SqliteBackup] could not send failure email: #{e.class}: #{e.message}"
  end

  def object_key = "comments-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.sqlite3.gz"
  def database_path = ActiveRecord::Base.connection_db_config.database
end
