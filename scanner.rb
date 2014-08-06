require "sqlite3"

class Scanner
  def initialize(dbf, root)
    @db = SQLite3::Database.new dbf

    @db.execute "CREATE TABLE IF NOT EXISTS changesets
      (id integer primary key, date integer, author text, commitid text,
      log text)"
    @db.execute "CREATE UNIQUE INDEX IF NOT EXISTS u_commitid ON changesets
      (commitid)"

    @db.execute "CREATE TABLE IF NOT EXISTS files
      (id integer primary key, file text)"
    @db.execute "CREATE UNIQUE INDEX IF NOT EXISTS u_file ON files
      (file)"

    @db.execute "CREATE TABLE IF NOT EXISTS revisions
      (id integer primary key, file_id integer, changeset_id integer,
      date integer, version text, author text, commitid text, log text)"
    @db.execute "CREATE UNIQUE INDEX IF NOT EXISTS u_revision ON revisions
      (file_id, version)"
    @db.execute "CREATE INDEX IF NOT EXISTS empty_changesets ON revisions
      (changeset_id)"
    @db.execute "CREATE INDEX IF NOT EXISTS cs_by_commitid ON revisions
      (commitid, changeset_id)"
    @db.execute "CREATE INDEX IF NOT EXISTS all_revs_by_author ON revisions
      (author, date)"

    @db.results_as_hash = true

    @root = (root + "/").gsub(/\/\//, "/")
  end

  def recursively_scan(dir = nil)
    if !dir
      dir = @root
    end

    puts "recursing into #{dir}"

    Dir.glob((dir + "/*").gsub(/\/\//, "/")).each do |f|
      if Dir.exists?(f)
        recursively_scan(f)
      elsif f.match(/,v$/)
        scan(f)
      end
    end
  end

  def scan(f)
    canfile = f[@root.length, f.length - @root.length].gsub(/\/Attic\//, "/")
    puts " scanning file #{canfile}"

    rcs = RCSFile.new(f)

    fid = @db.execute("SELECT id FROM files WHERE file = ?", [ canfile ]).first
    if !fid
      @db.execute("INSERT INTO files (file) VALUES (?)", [ canfile ])
      fid = @db.execute("SELECT id FROM files WHERE file = ?",
        [ canfile ]).first
    end
    raise if !fid

    rcs.revisions.each do |r,rev|
      rid = @db.execute("SELECT id, commitid FROM revisions WHERE " +
        "file_id = ? AND version = ?", [ fid["id"], r ]).first

      if rid
        if rid["commitid"] != rev.commitid
          puts "  updated #{r} to commitid #{rev.commitid}" +
            (rid["commitid"].to_s == "" ? "" : " from #{rid["commitid"]}")

          @db.execute("UPDATE revisions SET commitid = ? WHERE file_id = ? " +
            "AND version = ?", [ rev.commitid, fid["id"], rev.revision ])
        end
      else
        puts "  inserted #{r}, authored #{rev.date} by #{rev.author}" +
          (rev.commitid ? ", commitid #{rev.commitid}" : "")

        @db.execute("INSERT INTO revisions (file_id, date, version, author, " +
          "commitid, log) VALUES (?, ?, ?, ?, ?, ?)", [ fid["id"], rev.date,
          rev.revision, rev.author, rev.commitid, rev.log ])
      end
    end
  end

  def stray_commitids_to_changesets
    stray_commitids = @db.execute("SELECT DISTINCT author, commitid FROM " +
      "revisions WHERE commitid IS NOT NULL AND changeset_id IS NULL")
    stray_commitids.each do |row|
      csid = @db.execute("SELECT id FROM changesets WHERE commitid = ?",
        [ row["commitid"] ]).first
      if !csid
        @db.execute("INSERT INTO changesets (author, commitid) VALUES (?, ?)",
          [ row["author"], row["commitid"] ])
        csid = @db.execute("SELECT id FROM changesets WHERE commitid = ?",
          [ row["commitid"] ]).first
      end
      raise if !csid

      puts "commitid #{row["commitid"]} -> changeset #{csid["id"]}"

      @db.execute("UPDATE revisions SET changeset_id = ? WHERE commitid = ?",
        [ csid["id"], row["commitid"] ])
    end
  end

  def group_into_changesets
    new_sets = []
    last_row = {}
    cur_set = []

    @db.execute("SELECT * FROM revisions WHERE changeset_id IS NULL ORDER " +
    "BY author ASC, date ASC") do |row|
      # commits by the same author with the same log message (unless they're
      # initial imports - 1.1.1.1) within 30 seconds of each other are grouped
      # together
      if last_row.any? && row["author"] == last_row["author"] &&
      (row["log"] == last_row["log"] || row["log"] == "Initial revision" ||
      last_row["log"] == "Initial revision") &&
      row["date"].to_i - last_row["date"].to_i <= 30
        cur_set.push row["id"].to_i
      elsif !last_row.any?
        cur_set.push row["id"].to_i
      else
        if cur_set.any?
          new_sets.push cur_set
          cur_set = []
        end
        cur_set.push row["id"].to_i
      end

      last_row = row
    end

    if cur_set.any?
      new_sets.push cur_set
    end

    new_sets.each do |s|
      puts "new set with revision ids #{s.inspect}"
      @db.execute("INSERT INTO changesets (id) VALUES (NULL)")
      id = @db.execute("SELECT last_insert_rowid() AS id").first["id"]
      raise if !id

      # avoid an exception caused by passing too many variables
      s.each_slice(100) do |chunk|
        @db.execute("UPDATE revisions SET changeset_id = ? WHERE id IN (" +
          chunk.map{|a| "?" }.join(",") + ")", [ id ] + chunk)
      end
    end

    if @db.execute("SELECT * FROM revisions WHERE changeset_id IS NULL").any?
      raise "still have revisions with empty changesets"
    end
  end

  def fill_in_changeset_data
    cses = {}
    @db.execute("SELECT id, commitid FROM changesets WHERE date IS NULL") do |c|
      cses[c["id"]] = c["commitid"]
    end

    cses.each do |csid,comid|
      date = nil
      commitid = comid
      log = nil
      author = nil

      @db.execute("SELECT * FROM revisions WHERE changeset_id = ? ORDER BY " +
      "date ASC", [ csid ]) do |rev|
        if !date
          date = rev["date"]
        end

        if rev["log"] != "Initial revision"
          log = rev["log"]
        end

        if author && rev["author"] != author
          raise "authors different between revs of #{csid}"
        else
          author = rev["author"]
        end
      end

      if commitid.to_s == ""
        commitid = ""
        while commitid.length < 16
          c = rand(75) + 48
          if ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) ||
          (c >= 97 && c <= 122))
            commitid << c.chr
          end
        end
      end

      if !date
        raise "no date for changeset #{csid}"
      end

      puts "changeset #{csid} -> commitid #{commitid}"

      @db.execute("UPDATE changesets SET date = ?, commitid = ?, log = ?, " +
        "author = ? WHERE id = ?", [ date, commitid, log, author, csid ])
    end
  end

  def repo_surgery(tmp_dir, cvs_root, tree)
    puts "checking out repo \"#{tree}\" to #{tmp_dir}"

    Dir.chdir(tmp_dir)
    # don't pass -P because we'll need empty dirs around for Attic changes
    system("cvs", "-Q", "-d", cvs_root, "co", tree)

    Dir.chdir(tmp_dir + "/#{tree}")

    csid = nil
    @db.execute("SELECT
    files.file, changesets.commitid, changesets.author, changesets.date,
    revisions.version
    FROM revisions
    LEFT OUTER JOIN files ON files.id = file_id
    LEFT OUTER JOIN changesets ON revisions.changeset_id = changesets.id
    WHERE revisions.commitid IS NULL
    ORDER BY changesets.date ASC, files.file ASC") do |rev|
      if csid == nil || rev["commitid"] != csid
        puts " commit #{rev["commitid"]} at #{Time.at(rev["date"])} by " +
          rev["author"]
        csid = rev["commitid"]
      end

      puts "  #{rev["file"]} #{rev["version"]}"

      system("cvs", "-Q", "admin", "-C",
        "#{rev["version"]}:#{rev["commitid"]}", rev["file"].gsub(/,v$/, ""))
    end

    puts "cleaning up #{tmp_dir}/#{tree}"

    system("rm", "-rf", tmp_dir + "/#{tree}")
  end
end
