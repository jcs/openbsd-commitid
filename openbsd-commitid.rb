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

PWD = File.dirname(__FILE__)

require PWD + "/lib/db"
require PWD + "/lib/scanner"
require PWD + "/lib/rcsfile"
require PWD + "/lib/rcsrevision"
require PWD + "/lib/outputter"

CVSROOT = "/var/cvs-commitid/"
CVSTMP = "/var/cvs-tmp/"
CVSTREES = [ "src", "ports", "www", "xenocara" ]

GENESIS = "01-f96d46480b33dcec5924884fef54166e169fc08d19f1d1812f5cd2d1f704219a-0000000"

CVSTREES.each do |tree|
  if !Dir.exists?("#{CVSROOT}/#{tree}")
    next
  end

  sc = Scanner.new(PWD + "/db/openbsd-#{tree}.db", "#{CVSROOT}/#{tree}/")

  if tree == "src"
    # these revisions didn't get proper commitids with the others in the
    # changeset, so fudge them
    sc.commitid_hacks = {
      "sys/dev/pv/xenvar.h,v" => {
        "1.1" => "Ij2SOB19ATTH0yEx",
        "1.2" => "pq3FAYuwXteAsF4d",
        "1.3" => "C8vFI0RNH9XPJUKs",
      },
      "usr.bin/mg/theo.c,v" => {
        "1.144" => "gSveQVkxMLs6vRqK",
        "1.145" => "GbEBL4CfPvDkB8hj",
        "1.146" => "8rkHsVfUx5xgPXRB",
      },
    }

    # some rcs files have manually edited history that we need to work around
    sc.prev_revision_hacks = {
      # initial history gone?
      "sbin/isakmpd/pkcs.c,v" => { "1.4" => "0" },
      # 1.6 gone
      "sys/arch/sun3/sun3/machdep.c,v" => { "1.7" => "1.5" },
    }
  end

  # walk the directory of RCS files, create a "files" record for each one,
  # then run `rlog` on it and create a "revisions" record for each
  sc.recursively_scan

  # group revisions into changesets by date/author/message, or for newer
  # commits, their stored commitid
  sc.group_into_changesets

  # make sure every revision is accounted for
  sc.stray_commitids_to_changesets

  # assign a canonical date/message/order to each changeset
  sc.fill_in_changeset_data

  # check out the cvs tree in CVSTMP/tree and place each dead-1.1 file at its
  # initial non-dead revision found during `rlog`
  sc.stage_tmp_cvs(CVSTMP, CVSROOT, tree)

  # calculate a hash for each commit by running 'cvs show' on it, and store it
  # in the commitids-{tree} file
  sc.recalculate_commitids(CVSTMP, CVSROOT, tree, GENESIS)

  # and finally, update every revision of every file and write its calculated
  # commitid, possibly replacing the random one already there
  sc.repo_surgery(CVSTMP, CVSROOT, tree)
end
