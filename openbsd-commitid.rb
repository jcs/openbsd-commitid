#!/usr/bin/env ruby

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

  if tree == "src"
    # gcc has an old INSTALL file that later became a directory, so checking
    # out -r1.1 of the tree will throw an error when it tries to mkdir over the
    # existing file.  move it to some other name since it was deleted long ago
    if File.exists?(CVSROOT + "src/gnu/usr.bin/gcc/Attic/INSTALL,v")
      system("mv", "-f", CVSROOT + "src/gnu/usr.bin/gcc/Attic/INSTALL,v",
        CVSROOT + "src/gnu/usr.bin/gcc/Attic/INSTALL.old,v")
    end
  end

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
