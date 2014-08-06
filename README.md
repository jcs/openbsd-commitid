###OpenBSD commitid generator

A work in progress to assign `commitid` identifiers to all files in OpenBSD's
CVS trees for commits before `commitid` functionality was enabled.

####Usage

Paths used here are hard-coded in `openbsd-commitid.rb`.

1. Download pristine sources to `/var/cvs`:

       $ cvsync

2. Duplicate just-downloaded tree to `/var/cvs-commitid`, since these files
will get modified:

       $ rsync -a --delete /var/cvs/. /var/cvs-commitid/.

3. Run this script:

       $ ruby openbsd-commitid.rb

**NOTE**: `rlog` in path must be modified to end revisions with `[...]---###`,
not just a line of dashes since those appear in some commit messages.  This
allows the script to accurately separate each revision from `rlog`.  This
change will not be committed, and is included as a patch here.

**NOTE**: This script relies on a newly added `-C` flag to `cvs admin`, which
sets a `commitid` in an RCS file.  This change has not yet been committed and
is included as a patch here.

####Details

This script does the following steps:

1. Recurse a directory of RCS ,v files (`/var/cvs-commitid/`), creating a
"files" record for each one and marking whether it's now in the Attic.

2. Run `rlog` on each RCS file, parsing the output and creating a "revisions"
record with each revision's author, date, version, commitid (if present), and
log message.

3. Fetch all revisions (not already matched to a changeset) ordered by author
then date, and bundle them into changesets creating new "changesets" records
for each, then updating each "revisions" record with the new changeset id.  By
sorting all commits by author name, it's possible to accurately find all files
touched by an author in the same commit.

4. For each newly created "changesets" record, update them with a definitive
timestamp, log message, author, and commitid (creating a new one if needed)
based on all of the "revisions" with that changeset id.

5. Do a `cvs checkout` from `/var/cvs-commitid/` to a temporary directory
created in `/var/cvs-tmp/`.

6. For each "revisions" record of each "files" record that doesn't have a
recorded `commitid` (meaning this script generated one while bundling it into a
"changesets" record), run `cvs admin -C` to assign the `commitid` to that
revision in the RCS `,v` file in `/var/cvs-commitid/`.  For files that are
currently in the Attic, a `cvs up -r1.1` is run on the file first to pull it
out of the Attic.  This is required before running `cvs admin` since `cvs` only
uses the `CVS/Entries` file in each directory to determine that the file
exists, failing (silently!) when the file is not found.

7. `rm -rf` the temporary checked-out directory in `/var/cvs-tmp/` since the
changes are now all present in the `/var/cvs-commitid/` tree.

These steps are performed for each of the `src`, `ports`, `www`, and `xenocara`
trees.
