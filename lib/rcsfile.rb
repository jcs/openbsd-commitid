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
