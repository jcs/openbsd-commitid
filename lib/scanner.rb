class Scanner
  attr_accessor :outputter, :db

  # how long commits by the same author with the same commit message can be
  # from each other and still be grouped in the same changeset
  MAX_GROUP_WINDOW = (60 * 5)

  def initialize(dbf, root)
    @db = Db.new dbf
    @root = (root + "/").gsub(/\/\//, "/")
    @outputter = Outputter.new(self)
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
    stat = File.stat(f)
    canfile = f[@root.length, f.length - @root.length].gsub(/(^|\/)Attic\//,
      "/").gsub(/^\/*/, "")

    fid = @db.execute("SELECT id, first_undead_version, size FROM files " +
      "WHERE file = ?", [ canfile ]).first
    if fid && fid["size"].to_i > 0 && fid["size"].to_i == stat.size
      return
    end

    puts " scanning file #{canfile}"

    rcs = RCSFile.new(f)

    if fid
      if fid["first_undead_version"] != rcs.first_undead_version
        @db.execute("UPDATE files SET first_undead_version = ? WHERE id = ?",
          [ rcs.first_undead_version, fid["id"] ])
      end
    else
      @db.execute("INSERT INTO files (file, first_undead_version) VALUES " +
        "(?, ?)", [ canfile, rcs.first_undead_version ])
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
            "AND version = ?", [ rev.commitid, fid["id"], rev.version ])
        end
      else
        puts "  inserted #{r}, authored #{rev.date} by #{rev.author}" +
          (rev.commitid ? ", commitid #{rev.commitid}" : "")

        @db.execute("INSERT INTO revisions (file_id, date, version, author, " +
          "commitid, state, log) VALUES (?, ?, ?, ?, ?, ?, ?)",
          [ fid["id"], rev.date, rev.version, rev.author, rev.commitid,
          rev.state, rev.log ])
      end
    end

    @db.execute("UPDATE files SET size = ? WHERE id = ?",
      [ stat.size, fid["id"] ])
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

    # TODO: don't conditionalize with null changeset_ids, to allow this to run
    # incrementally and match new commits to old changesets
    @db.execute("SELECT * FROM revisions WHERE changeset_id IS NULL ORDER " +
    "BY author ASC, date ASC") do |row|
      # commits by the same author with the same log message (unless they're
      # initial imports - 1.1.1.1) within a small timeframe are grouped
      # together
      if last_row.any? && row["author"] == last_row["author"] &&
      (row["log"] == last_row["log"] || row["log"] == "Initial revision" ||
      last_row["log"] == "Initial revision") &&
      row["date"].to_i - last_row["date"].to_i <= MAX_GROUP_WINDOW
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
    puts "checking out #{tree} from #{cvs_root} to #{tmp_dir}"

    Dir.chdir(tmp_dir)

    # for a deleted file to be operated by with cvs admin, it must be
    # present in the CVS/Entries files, so check out all files at rev 1.1 so we
    # know they will not be deleted.  otherwise cvs admin will fail silently
    system("cvs", "-Q", "-d", cvs_root, "co", "-r1.1", tree) ||
      raise("cvs checkout returned non-zero")

    # but if any files were added on a branch or somehow have a weird history,
    # their 1.1 revision will be dead so check out any non-dead revision of
    # those files
    dead11s = {}
    @db.execute("SELECT
    file, first_undead_version
    FROM files
    WHERE first_undead_version NOT LIKE '1.1'") do |rev|
      dead11s[rev["file"]] = rev["first_undead_version"]
    end

    dead11s.each do |file,rev|
      confile = file.gsub(/,v$/, "")

      puts " checking out non-dead revision #{rev} of #{confile}"

      system("cvs", "-Q", "-d", cvs_root, "co", "-r#{rev}",
        "#{tree}/#{confile}") ||
        raise("cvs co -r#{rev} #{confile} failed")
    end
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

      output = nil
      IO.popen(ca = [ "cvs", "admin", "-C",
      "#{rev["version"]}:#{rev["commitid"]}",
      rev["file"].gsub(/,v$/, "") ]) do |admin|
        output = admin.read
      end

      if !output.match(/RCS file:/)
        raise "failed cvs admin command #{ca.inspect}"
      end
    end

    puts "cleaning up #{tmp_dir}/#{tree}"

    system("rm", "-rf", tmp_dir + "/#{tree}") ||
      raise("rm of #{tmp_dir}/#{tree} failed")
  end
end
