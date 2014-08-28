require "sqlite3"

class Db
  def initialize(dbf)
    @db = SQLite3::Database.new dbf

    @db.execute "CREATE TABLE IF NOT EXISTS changesets
      (id INTEGER PRIMARY KEY, date INTEGER, author TEXT, commitid TEXT,
      log TEXT)"
    @db.execute "CREATE UNIQUE INDEX IF NOT EXISTS u_commitid ON changesets
      (commitid)"

    @db.execute "CREATE TABLE IF NOT EXISTS files
      (id INTEGER PRIMARY KEY, file TEXT, first_undead_version TEXT)"
    @db.execute "CREATE UNIQUE INDEX IF NOT EXISTS u_file ON files
      (file)"

    @db.execute "CREATE TABLE IF NOT EXISTS revisions
      (id INTEGER PRIMARY KEY, file_id INTEGER, changeset_id INTEGER,
      date INTEGER, version TEXT, author TEXT, commitid TEXT, log TEXT,
      state TEXT)"
    @db.execute "CREATE UNIQUE INDEX IF NOT EXISTS u_revision ON revisions
      (file_id, version)"
    @db.execute "CREATE INDEX IF NOT EXISTS empty_changesets ON revisions
      (changeset_id)"
    @db.execute "CREATE INDEX IF NOT EXISTS cs_by_commitid ON revisions
      (commitid, changeset_id)"
    @db.execute "CREATE INDEX IF NOT EXISTS all_revs_by_author ON revisions
      (author, date)"
    @db.execute "CREATE INDEX IF NOT EXISTS all_revs_by_version_and_state ON
      revisions (version, state)"

    @db.results_as_hash = true
  end

  def execute(*args)
    if block_given?
      @db.execute(*args) do |row|
        yield row
      end
    else
      @db.execute(*args)
    end
  end
end
