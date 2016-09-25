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

class Outputter
  def initialize(scanner)
    @scanner = scanner
  end

  def changelog(domain, fh)
    puts "writing changelog to #{fh.path}"

    last = {}
    files = []

    printlog = Proc.new {
      fh.puts "Changes by:     #{last["author"]}@#{domain}   " <<
        Time.at(last["date"].to_i).strftime("%Y/%m/%d %H:%M:%S")
      if last["commitid"].to_s != ""
        fh.puts "Commitid:       #{last["commitid"]}"
      end
      if last["branch"].to_s != ""
        fh.puts "Branch:         #{last["branch"]}"
      end
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
    changesets.csorder, changesets.date, changesets.author,
    changesets.commitid, changesets.log, files.file, revisions.branch
    FROM changesets
    LEFT OUTER JOIN revisions ON revisions.changeset_id = changesets.id
    LEFT OUTER JOIN files ON revisions.file_id = files.id
    ORDER BY changesets.csorder, files.file") do |csfile|
      if csfile["csorder"] == last["csorder"]
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

  def history(fh)
    puts "writing history to #{fh.path}"

    last = {}
    files = []

    printlog = Proc.new {
      fh.puts [
        Time.at(last["date"].to_i).strftime("%Y/%m/%d %H:%M:%S"),
        last["author"],
        last["commitid"],
        last["log"].to_s.split("\n").first,
        files.map{|f| f.gsub(/,v$/, "") }.join(", "),
      ].join("\t")
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
