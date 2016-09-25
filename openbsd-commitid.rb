#!/usr/bin/env ruby
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

DIR = File.dirname(__FILE__) + "/lib/"

require DIR + "db"
require DIR + "scanner"
require DIR + "rcsfile"
require DIR + "rcsrevision"
require DIR + "outputter"

CVSROOT = "/var/cvs-commitid/"
CVSTMP = "/var/cvs-tmp/"
CVSTREES = [ "src", "ports", "www", "xenocara" ]

CVSTREES.each do |tree|
  if Dir.exists?("#{CVSTMP}/#{tree}/CVS")
    raise "clean out #{CVSTMP} first"
  end
end

PWD = Dir.pwd

CVSTREES.each do |tree|
  sc = Scanner.new(PWD + "/db/openbsd-#{tree}.db", "#{CVSROOT}/#{tree}/")
  sc.recursively_scan
  sc.group_into_changesets
  sc.stray_commitids_to_changesets
  sc.fill_in_changeset_data

  sc.repo_surgery(CVSTMP, CVSROOT, tree)

  sc.outputter.changelog("cvs.openbsd.org",
    f = File.open("out/Changelog-#{tree}", "w+"))
  f.close

  sc.outputter.history(f = File.open("out/history-#{tree}", "w+"))
  f.close

  sc.outputter.dup_script(f = File.open("out/add_commitids_to_#{tree}.sh",
    "w+"), tree)
  f.close
end
