# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SqliteBackup do
  let(:backup_config) do
    BackupConfig.build('R2_ACCESS_KEY_ID' => 'k', 'R2_SECRET_ACCESS_KEY' => 's',
                       'R2_ENDPOINT' => 'https://acct.r2.cloudflarestorage.com')
  end

  def build_source_db(path)
    SQLite3::Database.new(path) do |db|
      db.execute('CREATE TABLE comments (id INTEGER PRIMARY KEY, body TEXT)')
      db.execute("INSERT INTO comments (body) VALUES ('one'), ('two'), ('three')")
    end
  end

  # Reverse the backup (gunzip -> open as SQLite) so we can prove the snapshot is intact
  def rows_in_backup(gz_body)
    raw = Zlib::GzipReader.new(StringIO.new(gz_body)).read
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'restored.sqlite3')
      File.binwrite(path, raw)
      count = nil
      SQLite3::Database.new(path) { |db| count = db.execute('SELECT COUNT(*) FROM comments').first.first }
      count
    end
  end

  def run_backup = described_class.run(config: backup_config)

  describe '.run' do
    let(:source_dir) { Dir.mktmpdir }
    let(:source_db) { File.join(source_dir, 'source.sqlite3') }

    before do
      build_source_db(source_db)
      allow(described_class).to receive(:database_path).and_return(source_db)
    end

    after { FileUtils.remove_entry(source_dir, true) }

    context 'when everything succeeds' do
      let(:uploaded) { {} }

      before do
        allow(R2Uploader).to receive(:put) { |**kwargs| uploaded.merge!(kwargs) }
        run_backup
      end

      it 'uploads a gzipped snapshot under a timestamped key', :aggregate_failures do
        expect(uploaded[:key]).to match(/\Acomments-\d{8}T\d{6}Z\.sqlite3\.gz\z/)
        expect(uploaded[:content_type]).to eq(SqliteBackup::CONTENT_TYPE)
        expect(uploaded[:config]).to eq(backup_config)
      end

      it 'uploads an intact snapshot of the database' do
        expect(rows_in_backup(uploaded[:body])).to eq(3)
      end
    end

    context 'when the snapshot fails its integrity check' do
      before do
        allow(described_class).to receive(:integrity_ok?).and_return(false)
        allow(BackupFailureEmail).to receive(:deliver_for)
        allow(R2Uploader).to receive(:put)
      end

      it 'raises, emails the moderator, and never uploads', :aggregate_failures do
        expect { run_backup }.to raise_error(SqliteBackup::IntegrityError)
        expect(BackupFailureEmail).to have_received(:deliver_for).with(an_instance_of(SqliteBackup::IntegrityError))
        expect(R2Uploader).not_to have_received(:put)
      end
    end

    context 'when the upload fails' do
      let(:upload_error) { R2Uploader::TransientUploadError.new('503') }

      before do
        allow(R2Uploader).to receive(:put).and_raise(upload_error)
        allow(BackupFailureEmail).to receive(:deliver_for)
      end

      it 're-raises the error after emailing the moderator', :aggregate_failures do
        expect { run_backup }.to raise_error(upload_error)
        expect(BackupFailureEmail).to have_received(:deliver_for).with(upload_error)
      end
    end

    context 'when sending the failure email also fails' do
      before do
        allow(R2Uploader).to receive(:put).and_raise(R2Uploader::UploadError, 'boom')
        allow(BackupFailureEmail).to receive(:deliver_for).and_raise(StandardError, 'mailer down')
      end

      it 'still raises the original backup error, not the mailer error' do
        expect { run_backup }.to raise_error(R2Uploader::UploadError, 'boom')
      end
    end
  end

  describe '.database_path' do
    it 'resolves to the database the app is connected to' do
      expect(described_class.database_path).to end_with('comments_test.sqlite3')
    end
  end
end
