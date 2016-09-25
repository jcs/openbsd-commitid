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
  attr_accessor :version, :date, :author, :state, :lines, :commitid, :log

  # str: "revision 1.7\ndate: 1996/12/14 12:17:33;  author: mickey;  state: Exp;  lines: +3 -3;\n-Wall'ing."
  def initialize(str)
    @version = nil
    @date = 0
    @author = nil
    @state = nil
    @lines = nil
    @commitid = nil
    @log = nil

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

    @version = lines.first.scan(/^revision ([\d\.]+)($|\tlocked by)/).first.first
    # -> "1.7"

    # date/author/state/lines/commitid line
    lines[1].split(/;[ \t]*/).each do |piece|
      kv = piece.split(": ")
      self.send(kv[0] + "=", kv[1])
    end
    # -> @date = "1996/12/14 12:17:33", @author = "mickey", ...

    if m = @date.match(/^\d\d\d\d\/\d\d\/\d\d \d\d:\d\d:\d\d$/)
      @date = DateTime.parse(@date).strftime("%s").to_i
    else
      raise "invalid date #{@date}"
    end
    # -> @date = 850565853

    @log = lines[2, lines.count].join("\n")
  end
end
