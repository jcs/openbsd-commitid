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

class Scanner
  attr_accessor :outputter, :db, :commitid_hacks, :prev_revision_hacks

  # how long commits by the same author with the same commit message can be
  # from each other and still be grouped in the same changeset
  MAX_GROUP_WINDOW = (60 * 5)

  def initialize(dbf, root)
    @db = Db.new dbf
    @root = (root + "/").gsub(/\/\//, "/")
    @outputter = Outputter.new(self)
    @prev_revision_hacks = {}
    @commitid_hacks = {}
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
    cksum = ""
    IO.popen([ "cksum", "-q", f ]) do |c|
      parts = c.read.force_encoding("iso-8859-1").split(" ")
      if parts.length != 2
        raise "invalid output from cksum: #{parts.inspect}"
      end

      cksum = parts[0].encode("utf-8")
    end

    canfile = f[@root.length, f.length - @root.length].gsub(/(^|\/)Attic\//,
      "/").gsub(/^\/*/, "")

    fid = @db.execute("SELECT id, first_undead_version, cksum FROM files " +
      "WHERE file = ?", [ canfile ]).first
    if fid && fid["cksum"].to_s == cksum
      return
    end

    puts " scanning file #{canfile}"

    rcs = RCSFile.new(f)

    @db.execute("BEGIN")

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

    if @commitid_hacks && @commitid_hacks[canfile]
      @commitid_hacks[canfile].each do |v,cid|
        if rcs.revisions[v].commitid &&
        rcs.revisions[v].commitid != cid
          raise "hack for #{canfile}:#{v} commitid of #{cid.inspect} would " +
            "overwrite #{rcs.revisions[v].commitid}"
        end

        puts " faking commitid for revision #{v} -> #{cid}"
        rcs.revisions[v].commitid = cid
      end
    end

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
        # files added on branches/imports have unhelpful commit messages with
        # the helpful ones on the branch versions, so copy them over while
        # we're here
        if rev.log.to_s == "Initial revision"
          if r == "1.1" && rcs.revisions["1.1.1.1"]
            rev.log = rcs.revisions["1.1.1.1"].log
            puts "  revision #{r} using log from 1.1.1.1"
          else
            puts "  revision #{r} keeping log #{rev.log.inspect}, no 1.1.1.1"
          end
        elsif m = rev.log.to_s.
        match(/\Afile .+? was initially added on branch ([^\.]+)\.\z/)
          brver = nil
          if br = rcs.symbols[m[1]]
            brver = RCSRevision.first_branch_version_of(br)
            if !rcs.revisions[brver]
              if rcs.revisions[brver + ".1"]
                brver += ".1"
              else
                puts "  revision #{r} keeping log #{rev.log.inspect}, no #{brver}"
                brver = nil
              end
            end
          end

          if brver
            rev.log = rcs.revisions[brver].log
            puts "  revision #{r} using log from #{brver}"

            # but consider this trunk revision on the branch the file was added
            # on, just so we keep it in the same changeset
            rev.branch = rcs.revisions[brver].branch
          else
            puts "  revision #{r} keeping log #{rev.log.inspect}, no #{m[1]}"
          end
        end

        puts "  inserted #{r}" +
          (rev.branch ? " (branch #{rev.branch})" : "") +
          ", authored #{rev.date} by #{rev.author}" +
          (rev.commitid ? ", commitid #{rev.commitid}" : "")

        @db.execute("INSERT INTO revisions (file_id, date, version, author, " +
          "commitid, state, log, branch) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
          [ fid["id"], rev.date, rev.version, rev.author, rev.commitid,
          rev.state, rev.log, rev.branch ])
        rid = { "id" => @db.last_insert_row_id }
      end

      vbs = @db.execute("SELECT branch FROM vendor_branches WHERE " +
        "revision_id = ?", [ rid["id"] ]).map{|r| r["branch"] }.flatten

      rev.vendor_branches.each do |vb|
        if !vbs.include?(vb)
          puts "   inserting vendor branch #{vb}"
          @db.execute("INSERT INTO vendor_branches (revision_id, branch) " +
            "VALUES (?, ?)", [ rid["id"], vb ])
        end
      end

      vbs.each do |vb|
        if !rev.vendor_branches.include?(vb)
          @db.execute("DELETE FROM vendor_branches WHERE revision_id = ? " +
            "AND branch = ?", [ rid["id"], vb ])
        end
      end
    end

    @db.execute("UPDATE files SET cksum = ? WHERE id = ?",
      [ cksum, fid["id"] ])

    @db.execute("COMMIT")
  end

  def group_into_changesets
    puts "grouping into changesets"

    new_sets = []
    last_row = {}
    cur_set = []

    @db.execute("BEGIN")

    # commits by the same author with the same log message within a small
    # timeframe are grouped together
    @db.execute("SELECT * FROM revisions WHERE changeset_id IS NULL ORDER " +
    "BY author ASC, branch ASC, commitid ASC, date ASC") do |row|
      if last_row.any? &&
      row["author"] == last_row["author"] &&
      row["branch"] == last_row["branch"] &&
      row["log"] == last_row["log"] &&
      row["commitid"] == last_row["commitid"] &&
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
      puts " new set with revision ids #{s.inspect}"
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

    @db.execute("COMMIT")
  end

  def stray_commitids_to_changesets
    @db.execute("BEGIN")

    puts "finding stray commitids"

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

      puts " commitid #{row["commitid"]} -> changeset #{csid["id"]}"

      @db.execute("UPDATE revisions SET changeset_id = ? WHERE commitid = ?",
        [ csid["id"], row["commitid"] ])
    end

    @db.execute("COMMIT")
  end

  def fill_in_changeset_data
    puts "assigning dates to changesets"

    @db.execute("BEGIN")

    cses = {}
    @db.execute("SELECT id, commitid FROM changesets WHERE date IS NULL") do |c|
      cses[c["id"]] = c["commitid"]
    end

    # create canonical dates for each changeset, so we can pull them back out
    # in order
    cses.each do |csid,comid|
      date = nil
      commitid = comid
      log = nil
      author = nil
      branch = nil

      @db.execute("SELECT * FROM revisions WHERE changeset_id = ? ORDER BY " +
      "date ASC", [ csid ]) do |rev|
        if !date
          date = rev["date"]
        end

        if log && rev["log"] != log
          raise "logs different between revs of #{csid}"
        else
          log = rev["log"]
        end

        if author && rev["author"] != author
          raise "authors different between revs of #{csid}"
        else
          author = rev["author"]
        end

        if branch && rev["branch"] != branch
          raise "branches different between revs of #{csid}"
        else
          branch = rev["branch"]
        end
      end

      if !date
        raise "no date for changeset #{csid}"
      end

      @db.execute("UPDATE changesets SET date = ?, log = ?, author = ?, " +
        "branch = ? WHERE id = ?", [ date, log, author, branch, csid ])
    end

    @db.execute("COMMIT")

    puts "assigning changeset order"

    cses = []
    @db.execute("SELECT id FROM changesets WHERE csorder IS NULL ORDER BY " +
    "date, author") do |c|
      cses.push c["id"]
    end

    highestcs = @db.execute("SELECT MAX(csorder) AS lastcs FROM changesets " +
      "WHERE csorder IS NOT NULL").first["lastcs"].to_i

    @db.execute("BEGIN")
    cses.each do |cs|
      highestcs += 1
      @db.execute("UPDATE changesets SET csorder = ?, commitid = NULL WHERE " +
        "id = ?", [ highestcs, cs ])
    end
    @db.execute("COMMIT")
  end

  def stage_tmp_cvs(tmp_dir, cvs_root, tree)
    # for a deleted file to be operated by with cvs admin, it must be
    # present in the CVS/Entries files, so check out all files at rev 1.1 so we
    # know they will not be deleted.  otherwise cvs admin will fail silently
    if File.exists?("#{tmp_dir}/#{tree}/CVS/Entries")
      puts "updating #{tmp_dir}#{tree} from #{cvs_root}"
      Dir.chdir("#{tmp_dir}/#{tree}")
      system("cvs", "-Q", "-d", cvs_root, "update", "-PAd", "-r1.1") ||
        raise("cvs update returned non-zero")
    else
      puts "checking out #{cvs_root}#{tree} to #{tmp_dir}"
      Dir.chdir(tmp_dir)
      system("cvs", "-Q", "-d", cvs_root, "co", "-r1.1", tree) ||
        raise("cvs checkout returned non-zero")
    end

    Dir.chdir(tmp_dir)

    # but if any files were added on a branch or somehow have a weird history,
    # their 1.1 revision will be dead so check out any non-dead revision of
    # those files
    dead11s = {}
    @db.execute("SELECT
    file, first_undead_version
    FROM files
    WHERE first_undead_version NOT LIKE '1.1' AND
    id IN (SELECT file_id FROM revisions WHERE commitid IS NULL)") do |rev|
      dead11s[rev["file"]] = rev["first_undead_version"]
    end

    dead11s.each do |file,rev|
      confile = file.gsub(/,v$/, "")

      puts " checking out non-dead revision #{rev} of #{confile}"

      system("cvs", "-Q", "-d", cvs_root, "co", "-r#{rev}",
        "#{tree}/#{confile}") ||
        raise("cvs co -r#{rev} #{confile} failed")
    end

    Dir.chdir("#{tmp_dir}/#{tree}")
  end

  def recalculate_commitids(tmp_dir, cvs_root, tree, genesis)
    Dir.chdir(tmp_dir + "/#{tree}")

    puts "recalculating new commitids from genesis #{genesis}"

    gfn = "#{cvs_root}/CVSROOT/commitid_genesis"
    if File.exists?(gfn) && File.read(gfn).strip != genesis
      raise "genesis in #{gfn} is not #{genesis.inspect}"
    else
      File.write("#{cvs_root}/CVSROOT/commitid_genesis", genesis + "\n")
    end

    changesets = []
    @db.execute("SELECT id, csorder, commitid FROM changesets
    ORDER BY csorder ASC") do |cs|
      changesets.push cs
    end

    puts " writing commitids-#{tree} (#{changesets.length} " +
      "changeset#{changesets.length == 1 ? "" : "s"})"

    commitids = File.open("#{cvs_root}/CVSROOT/commitids-#{tree}", "w+")

    # every changeset needs to know the revisions of its files from the
    # previous change, taking into account branches.  we can easily calculate
    # this, but we should make sure that calculated revision actually exists
    files = {}
    @db.execute("SELECT id, file FROM files") do |row|
      files[row["id"]] = row["file"]
    end
    files.each do |id,file|
      vers = []

      @db.execute("SELECT version FROM revisions WHERE file_id = ?",
      [ id ]) do |rev|
        vers.push rev["version"]
      end

      vers.each do |rev|
        if prev_revision_hacks[file] && (hpre = prev_revision_hacks[file][rev])
          puts " faking previous revision of #{file} #{rev} -> #{hpre}"
          pre = hpre
        else
          pre = RCSRevision.previous_of(rev)
        end

        if pre != "0" && !vers.include?(pre)
          raise "#{file}: revision #{rev} previous #{pre} not found"
        end
      end
    end
    files = {}

    # for each changeset with no commitid, store it in the commitids-* file
    # with a temporary commitid of just its changeset number, do a 'cvs show'
    # on it to calculate the actual commitid, then overwrite that hash in the
    # commitids file, and store our new one
    changesets.each do |cs|
      cline = []
      commitid = ""
      if cs["commitid"].to_s != ""
        commitid = cs["commitid"]
      else
        commitid = sprintf("01-%064d-%07d", cs["csorder"], cs["csorder"])
      end

      # order by length(revisions.version) to put 1.1 first, then 1.1.1.1, to
      # match 'cvs import'
      @db.execute("SELECT
      files.file, revisions.version, revisions.branch
      FROM revisions
      LEFT OUTER JOIN files ON files.id = revisions.file_id
      WHERE revisions.changeset_id = ?
      ORDER BY files.file ASC, LENGTH(revisions.version) ASC,
      revisions.version ASC", [ cs["id"] ]) do |rev|
        if cline.length == 0
          cline.push commitid
        end

        cline.push [ RCSRevision.previous_of(rev["version"]), rev["version"],
          rev["branch"].to_s, rev["file"].gsub(/,v$/, "") ].join(":")
      end

      pos = commitids.pos
      commitids.puts cline.join("\t")

      if cs["commitid"].to_s == ""
        commitids.fsync

        newcsum = `cvs show #{commitid} | tail -n +2 | cksum -a sha512/256`.strip
        if $?.exitstatus != 0
          raise "failed running cvs show #{commitid}"
        end

        # null
        if newcsum == "c672b8d1ef56ed28ab87c3622c5114069bdd3ad7b8f9737498d0c01ecef0967a"
          raise "failed getting new commitid from #{commitid}"
        end

        newid = sprintf("01-%64s-%07d", newcsum, cs["csorder"])

        @db.execute("UPDATE changesets SET commitid = ? WHERE id = ?",
          [ newid, cs["id"] ])

        puts " changeset #{cs["csorder"]} -> #{newid}"

        # go back, rewrite just our commitid, then get ready for the next line
        commitids.seek(pos)
        commitids.write(newid)
        commitids.seek(0, IO::SEEK_END)
        commitids.fsync
      else
        puts " changeset #{cs["csorder"]} == #{cs["commitid"]}"
      end
    end

    commitids.close
  end

  def repo_surgery(tmp_dir, cvs_root, tree)
    puts "updating commitids in rcs files at #{cvs_root} via #{tmp_dir}"

    Dir.chdir("#{tmp_dir}/#{tree}")

    # for each revision we have in the db (picked up from a scan) that has a
    # different commitid from what we assigned to its changeset, update the
    # commitid in the rcs file in the repo, and then our revisions records
    @db.execute("
    SELECT
    files.file, changesets.commitid, revisions.version, revisions.id AS revid,
    revisions.commitid AS revcommitid
    FROM revisions
    LEFT OUTER JOIN files ON files.id = revisions.file_id
    LEFT OUTER JOIN changesets ON revisions.changeset_id = changesets.id
    WHERE changesets.commitid != IFNULL(revisions.commitid, '')
    ORDER BY changesets.date ASC, files.file ASC") do |rev|
      puts [ "", rev["file"], rev["version"], rev["revcommitid"], "->",
        rev["commitid"] ].join(" ")

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

    # re-read commitids and update file checksums since we probably just
    # changed many of them, which will then update commitids in revisions table
    sc.recursively_scan
  end
end
