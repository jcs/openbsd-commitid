###OpenBSD commitid generator

A work in progress to assign `commitid` identifiers to all files in OpenBSD's
CVS trees for commits before `commitid` functionality was enabled.

####Usage

Paths used here are hard-coded in `openbsd-commitid.rb`.

1. Download pristine sources to `/var/cvs`:

       `$ cvsync`

2. Duplicate just-downloaded tree to `/var/cvs-commitid`, since these files
will get modified:

       `$ rsync -a --delete /var/cvs/. /var/cvs-commitid/.`

3. Run this script:

       `$ ruby openbsd-commitid.rb`

**NOTE**: This script relies on recently added changes to OpenBSD's `rlog`
and `cvs` tools:

- `cvs admin -C` to set a revision's `commitid`
- `rlog -E` and `rlog -S` to control the revision separators in `rlog`
  output, since the default line of dashes appears in old commit messages

####Details

This script does the following steps for each of the `src`, `ports`, `www`,
and `xenocara` trees.

1. Recurse a directory of RCS ,v files (`/var/cvs-commitid/`), create a
"files" record for each one.

2. Run `rlog` on each RCS file, parse the output and create a "revisions"
record with each revision's author, date, version, commitid (if present), and
log message.  Update the "files" record to note the first non-`dead` version
in the file.

3. Fetch all revisions not already matched to a changeset, ordered by author
then date, and bundle them into changesets.  Create a new "changesets" record
for each, then update each of those "revisions" records with the new changeset
id.  By sorting all commits by author and date, it's possible to accurately
find all files touched by an author in the same commit window.

4. For each newly created "changesets" record, update them with a definitive
timestamp, log message, author, and commitid (creating a new one if needed)
based on all of the "revisions" with that changeset id.

5. Do a `cvs checkout` from `/var/cvs-commitid/` to a temporary directory
created in `/var/cvs-tmp/`, checking out revision 1.1 of each file.  For each
file that has a first-non-`dead` version number that is not 1.1, do another
`cvs checkout` of that version of the file so that every file in the tree is
now present in the working checked-out tree.  This is required to operate on
deleted files (moved to the Attic) and files where version 1.1 does not exist,
such as those created on branches.

6. For each "revisions" record of each "files" record that doesn't have a
recorded `commitid` (meaning this script generated one while bundling it into a
"changesets" record), run `cvs admin -C` to assign the `commitid` to that
revision in the RCS `,v` file in `/var/cvs-commitid/`.

7. `rm -rf` the temporary checked-out directory in `/var/cvs-tmp/` since the
changes are now all present in the `/var/cvs-commitid/` tree.
