###OpenBSD commitid generator

A work in progress to assign CVS provenance-style `commitid` identifiers to
all revisions of all files in OpenBSD's CVS trees.

####Usage

Paths used here are hard-coded in `openbsd-commitid.rb`.

1. Download pristine sources to `/var/cvs`:

       `$ cvsync`

2. Duplicate just-downloaded tree to `/var/cvs-commitid`, since these files
will get modified:

       `$ rsync -a --delete /var/cvs/. /var/cvs-commitid/.`

3. Run this script:

       `$ ruby openbsd-commitid.rb`

**NOTE**: This script relies on recently added changes to OpenBSD's `rlog` and
`cvs` tools:

- `cvs admin -C` to set a revision's `commitid`
- `rlog -E` and `rlog -S` to control the revision separators in `rlog` output,
  since the default line of dashes appears in old commit messages

For details of how this script works, read `openbsd-commitid.rb`.
