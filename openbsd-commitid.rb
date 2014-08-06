#!/usr/bin/env ruby

$:.push "."

require "scanner"
require "rcsfile"
require "rcsrevision"

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
  sc = Scanner.new(PWD + "/openbsd-#{tree}.db", "#{CVSROOT}/#{tree}/")
  sc.recursively_scan
  sc.group_into_changesets
  sc.stray_commitids_to_changesets
  sc.fill_in_changeset_data

  # check out the tree from CVSROOT/#{tree} in a scratch space (CVSTMP), which
  # is just necessary to be able to issue "cvs admin" commands, which get
  # stored back in CVSROOT/#{tree}
  sc.repo_surgery(CVSTMP, CVSROOT, tree)
end
