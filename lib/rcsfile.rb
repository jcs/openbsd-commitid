class RCSFile
  attr_accessor :revisions, :first_undead_version

  def initialize(file)
    @revisions = {}

    # rcs modified to end revs in ###
    blocks = []
    IO.popen([ "rlog", file ]) do |rlog|
      # rlog modified to end revision and file separators with ###
      blocks = rlog.read.force_encoding("binary").
        split(/^(-{28}|={77})###\n?$/).
        reject{|b| b.match(/\A(-{28}|={77})\z/) }
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
