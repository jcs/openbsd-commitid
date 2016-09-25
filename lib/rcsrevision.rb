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

require "date"

class RCSRevision
  attr_accessor :rcsfile, :version, :date, :author, :state, :lines, :commitid,
    :log, :branch, :vendor_branches

  def self.previous_of(ver)
    nums = ver.split(".").map{|z| z.to_i }

    if nums.last == 1
      # 1.3.2.1 -> 1.3
      2.times { nums.pop }
    else
      # 1.3.2.2 -> 1.3.2.1
      nums[nums.count - 1] -= 1
    end

    outnum = nums.join(".")
    if outnum == ""
      return "0"
    else
      return outnum
    end
  end

  # 1.1.0.2 -> 1.1.2.1
  def self.first_branch_version_of(ver)
    nums = ver.split(".").map{|z| z.to_i }

    if nums[nums.length - 2] != 0
      return ver
    end

    last = nums.pop
    nums.pop
    nums.push last
    nums.push 1

    return nums.join(".")
  end

  def self.is_vendor_branch?(ver)
    !!ver.match(/^1\.1\.1\..*/)
  end

  def self.is_trunk?(ver)
    ver.split(".").count == 2
  end

  # str: "revision 1.7\ndate: 1996/12/14 12:17:33;  author: mickey;  state: Exp;  lines: +3 -3;\n-Wall'ing."
  def initialize(rcsfile, str)
    @rcsfile = rcsfile
    @version = nil
    @date = 0
    @author = nil
    @state = nil
    @lines = nil
    @commitid = nil
    @log = nil
    @branch = nil
    @vendor_branches = []

    lines = str.gsub(/^\s*/, "").split("\n")
    # -> [
    #   "revision 1.7",
    #   "date: 1996/12/14 12:17:33;  author: mickey;  state: Exp;  lines: +3 -3;",
    #   "-Wall'ing."
    # ]

    # strip out possible branches line in log
    if lines[2].to_s.match(/^branches:\s+([\d\.]+)/)
      lines.delete_at(2)
    end

    @version = lines.first.scan(/^revision ([\d\.]+)($|\tlocked by)/).first.
      first.encode("UTF-8")
    # -> "1.7"

    # date/author/state/lines/commitid line
    lines[1].split(/;[ \t]*/).each do |piece|
      kv = piece.split(": ")
      self.send(kv[0] + "=", kv[1].encode("UTF-8"))
    end
    # -> @date = "1996/12/14 12:17:33", @author = "mickey", ...

    if m = @date.match(/^\d\d\d\d\/\d\d\/\d\d \d\d:\d\d:\d\d$/)
      @date = DateTime.parse(@date).strftime("%s").to_i
    else
      raise "invalid date #{@date}"
    end
    # -> @date = 850565853

    @log = lines[2, lines.count].join("\n").encode("UTF-8",
      :invalid => :replace, :undef => :replace, :replace => "?")

    if @version.match(/^\d+\.\d+$/)
      # no branch
    elsif @version.match(/^1\.1\.1\./) ||
    (@version == "1.1.2.1" && @branch == nil)
      # vendor
      @rcsfile.symbols.each do |k,v|
        if v == "1.1.1"
          @vendor_branches.push k
        end
      end
    elsif m = @version.match(/^(\d+)\.(\d+)\.(\d+)\.\d+$/)
      # 1.2.2.3 -> 1.2.0.2
      sym = [ m[1], m[2], "0", m[3] ].join(".")
      @rcsfile.symbols.each do |s,v|
        if v == sym
          if @branch
            raise "version #{@version} matched two symbols (#{@branch}, #{s})"
          end

          @branch = s
        end
      end

      if !@branch && @rcsfile.symbols.values.include?(@version)
        # if there's an exact match, this was probably just an import done with
        # a vendor branch id (import -b)
      elsif !@branch
        # branch was deleted, but we don't want this appearing on HEAD, so call
        # it something
        @branch = "_branchless_#{@version.gsub(".", "_")}"
      end

      if @branch && @rcsfile.symbols[@branch] &&
      @rcsfile.symbols[@branch].match(/^1\.1\.0\.\d+$/)
        # this is also a vendor branch
        if !@vendor_branches.include?(@branch)
          @vendor_branches.push @branch
        end
      end
    else
      raise "TODO: handle version #{@version}"
    end
  end
end
