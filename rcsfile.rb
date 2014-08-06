class RCSFile
  attr_accessor :revisions

  def initialize(file)
    @revisions = {}

    # rcs modified to end revs in ###
    blocks = []
    IO.popen([ "rlog", file ]) do |rlog|
      blocks = rlog.read.force_encoding("binary").
        split(/^(-{28}|={77})###\n?$/).reject{|b| b.match(/^(-{28}|={77})$/) }
    end

    if !blocks.first.match(/^RCS file/)
      raise "file #{file} didn't come out of rlog properly"
    end

    blocks.shift
    blocks.each do |block|
      rev = RCSRevision.new(block)
      if @revisions[rev.revision]
        raise "duplicate revision #{rev.revision} in #{file}"
      end
      @revisions[rev.revision] = rev
    end
  end
end
