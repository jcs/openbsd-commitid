class Outputter
  def initialize(scanner)
    @scanner = scanner
  end

  def changelog(domain, fh)
    last = {}
    files = []

    printlog = Proc.new {
      fh.puts "Changes by:     #{last["author"]}@#{domain}   " <<
        Time.at(last["date"].to_i).strftime("%Y/%m/%d %H:%M:%S")
      fh.puts "Commitid:       #{last["commitid"]}"
      fh.puts ""
      fh.puts "Modified files:"

      # group files by directory
      dirs = {}
      files.each do |f|
        dir = f.split("/")
        file = dir.pop.gsub(/,v$/, "")

        if dir.length == 0
          dir = "."
        else
          dir = dir.join("/")
        end

        dirs[dir] ||= []
        if !dirs[dir].include?(file)
          dirs[dir].push file
        end
      end

      # print padded and wrapped directory and file lines
      dirs.each do |dir,fs|
        dl = "        #{dir}"
        if dir.length < 15
          (15 - dir.length).times do
            dl += " "
          end
        end
        dl += ":"
        fl = (72 - dl.length)
        cl = dl
        (fs.count + 1).times do
          if (f = fs.shift)
            if cl.length + f.length > 72
              fh.puts cl.gsub(/[ ]{8}/, "\t")
              cl = " " * dl.length
            end

            cl += " " + f
          else
            fh.puts cl.gsub(/[ ]{8}/, "\t")
            break
          end
        end
      end

      fh.puts ""
      fh.puts "Log message:"
      fh.puts last["log"]
      fh.puts ""
      fh.puts ""
    }

    @scanner.db.execute("SELECT
    changesets.date, changesets.author, changesets.commitid, changesets.log,
    files.file
    FROM changesets
    LEFT OUTER JOIN revisions ON revisions.changeset_id = changesets.id
    LEFT OUTER JOIN files ON revisions.file_id = files.id
    ORDER BY changesets.date, files.file") do |csfile|
      if csfile["commitid"] == last["commitid"]
        files.push csfile["file"]
      else
        if files.any?
          printlog.call
        end
        files = [ csfile["file"] ]
        last = csfile
      end
    end

    if last.any?
      printlog.call
    end
  end

  def dup_script(script, tree)
    script.puts "#!/bin/sh -x"
    script.puts "if [ \"$TMPCVSDIR\" = \"\" ]; then echo 'set $TMPCVSDIR'; " +
      "exit 1; fi"
    script.puts "if [ \"$CVSROOT\" = \"\" ]; then echo 'set $CVSROOT'; " +
      "exit 1; fi"
    script.puts ""
    script.puts "cd $TMPCVSDIR"
    script.puts "cvs -Q -d $CVSROOT co -r1.1 #{tree} || exit 1"
    script.puts ""

    dead11s = {}
    @scanner.db.execute("SELECT
    file, first_undead_version
    FROM files
    WHERE first_undead_version NOT LIKE '1.1'") do |rev|
      dead11s[rev["file"]] = rev["first_undead_version"]
    end

    dead11s.each do |file,rev|
      confile = file.gsub(/,v$/, "")

      script.puts "cvs -Q -d $CVSROOT co -r#{rev} '#{tree}/#{confile}' " +
        "|| exit 1"
    end

    script.puts ""
    script.puts "cd $TMPCVSDIR/#{tree}"

    csid = nil
    @scanner.db.execute("SELECT
    files.file, changesets.commitid, changesets.author, changesets.date,
    revisions.version
    FROM revisions
    LEFT OUTER JOIN files ON files.id = file_id
    LEFT OUTER JOIN changesets ON revisions.changeset_id = changesets.id
    WHERE revisions.commitid IS NULL
    ORDER BY changesets.date ASC, files.file ASC") do |rev|
      if csid == nil || rev["commitid"] != csid
        script.puts "# commit #{rev["commitid"]} at #{Time.at(rev["date"])} " +
          "by " + rev["author"]
        csid = rev["commitid"]
      end

      script.puts "cvs admin -C #{rev["version"]}:#{rev["commitid"]} '" +
        rev["file"].gsub(/,v$/, "") + "'"
    end
  end
end
