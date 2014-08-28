require "date"

class RCSRevision
  attr_accessor :version, :date, :author, :state, :lines, :commitid, :log

  # str: "revision 1.7\ndate: 1996/12/14 12:17:33;  author: mickey;  state: Exp;  lines: +3 -3;\n-Wall'ing."
  def initialize(str)
    @version = nil
    @date = 0
    @author = nil
    @state = nil
    @lines = nil
    @commitid = nil
    @log = nil

    lines = str.gsub(/^\s*/, "").split("\n")
    # -> [
    #   "revision 1.7",
    #   "date: 1996/12/14 12:17:33;  author: mickey;  state: Exp;  lines: +3 -3;",
    #   "-Wall'ing."
    # ]

    # strip out possible branches line in log
    if lines[2].to_s.match(/^branches:\s+([\d\.]+)/)
      lines.delete_at(2)
    end

    @version = lines.first.scan(/^revision ([\d\.]+)($|\tlocked by)/).first.first
    # -> "1.7"

    # date/author/state/lines/commitid line
    lines[1].split(/;[ \t]*/).each do |piece|
      kv = piece.split(": ")
      self.send(kv[0] + "=", kv[1])
    end
    # -> @date = "1996/12/14 12:17:33", @author = "mickey", ...

    if m = @date.match(/^\d\d\d\d\/\d\d\/\d\d \d\d:\d\d:\d\d$/)
      @date = DateTime.parse(@date).strftime("%s").to_i
    else
      raise "invalid date #{@date}"
    end
    # -> @date = 850565853

    @log = lines[2, lines.count].join("\n")
  end
end
