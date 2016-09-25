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

class RCSFile
  attr_accessor :revisions, :first_undead_version

  RCSEND = "==================OPENBSD_COMMITID_RCS_END=================="
  REVSEP = "------------------OPENBSD_COMMITID_REV_SEP------------------"

  def initialize(file)
    @revisions = {}

    blocks = []
    IO.popen([ "rlog", "-E#{RCSEND}", "-S#{REVSEP}", file ]) do |rlog|
      blocks = rlog.read.force_encoding("binary").
        split(/^(#{REVSEP}|#{RCSEND})\n?$/).
        reject{|b| b == RCSEND || b == REVSEP }
    end

    if !blocks.first.match(/^RCS file/)
      raise "file #{file} didn't come out of rlog properly"
    end

    blocks.shift
    blocks.each do |block|
      rev = RCSRevision.new(block)
      if @revisions[rev.version]
        raise "duplicate revision #{rev.version} in #{file}"
      end
      @revisions[rev.version] = rev
    end

    @first_undead_version = @revisions.values.
      # this has nothing to do with Gem, but it has a version comparator
      sort{|a,b| Gem::Version.new(a.version) <=> Gem::Version.new(b.version) }.
      select{|r| r.state != "dead" }.first.version
  end
end
