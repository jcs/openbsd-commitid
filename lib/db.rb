#
# Copyright (c) 2014, 2016 joshua stein <jcs@jcs.org>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. The name of the author may not be used to endorse or promote products
#    derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

require "sqlite3"

class Db
  def initialize(dbf)
    @db = SQLite3::Database.new dbf
    @db.results_as_hash = true

    @db.execute "CREATE TABLE IF NOT EXISTS changesets
      (id INTEGER PRIMARY KEY, date INTEGER, author TEXT, commitid TEXT,
      log TEXT, branch TEXT, csorder INTEGER)"
    @db.execute "CREATE UNIQUE INDEX IF NOT EXISTS u_cs_commitid ON changesets
      (commitid)"
    @db.execute "CREATE UNIQUE INDEX IF NOT EXISTS u_cs_csorder ON changesets
      (csorder)"
    @db.execute "CREATE INDEX IF NOT EXISTS cs_branch ON changesets (branch)"

    @db.execute "CREATE TABLE IF NOT EXISTS files
      (id INTEGER PRIMARY KEY, file TEXT, first_undead_version TEXT,
      cksum TEXT)"
    @db.execute "CREATE UNIQUE INDEX IF NOT EXISTS u_f_file ON files
      (file)"

    @db.execute "CREATE TABLE IF NOT EXISTS revisions
      (id INTEGER PRIMARY KEY, file_id INTEGER, changeset_id INTEGER,
      date INTEGER, version TEXT, author TEXT, commitid TEXT, log TEXT,
      state TEXT, branch TEXT)"
    @db.execute "CREATE UNIQUE INDEX IF NOT EXISTS u_r_revision ON revisions
      (file_id, version)"
    @db.execute "CREATE INDEX IF NOT EXISTS r_empty_changesets ON revisions
      (changeset_id)"
    @db.execute "CREATE INDEX IF NOT EXISTS r_cs_by_commitid ON revisions
      (commitid, changeset_id)"
    @db.execute "CREATE INDEX IF NOT EXISTS r_all_revs_by_author ON revisions
      (author, date)"
    @db.execute "CREATE INDEX IF NOT EXISTS r_all_revs_by_version_and_state ON
      revisions (version, state)"
    @db.execute "CREATE INDEX IF NOT EXISTS r_branch ON revisions (branch)"

    @db.execute("CREATE TABLE IF NOT EXISTS vendor_branches
      (id INTEGER PRIMARY KEY, revision_id INTEGER, branch TEXT)")
    @db.execute("CREATE INDEX IF NOT EXISTS vb_revision ON vendor_branches
      (revision_id)")
    @db.execute("CREATE INDEX IF NOT EXISTS vb_branch_branch ON vendor_branches
      (branch)")
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

  def last_insert_row_id
    @db.last_insert_row_id
  end
end
