require 'metasm/main'

module Metasm

class Sstic2013 < CPU

  class Reg
    class << self
      attr_accessor :s_to_i, :i_to_s
    end

    @i_to_s = (0..7).inject({}) { |h, i| h.update i => "r#{i}" }
    @s_to_i = @i_to_s.invert

    attr_accessor :i
    def initialize(i)
      @i = i
    end

    def symbolic(orig=nil) ; to_s.to_sym ; end

    def self.from_str(s)
      raise "Bad name name #{s.inspect}" if not x = @s_to_i[s]
      new(x)
    end
  end # end of class Reg

  class Accu
    def symbolic(orig=nil) ; :accu ; end

    def self.from_str(s)
      raise "Bad name name #{s.inspect}" unless x == "accu"
      new
    end
  end # end of class Accu

  class Memref
    attr_accessor :base
    def initialize(base)
      @base = base
    end

    def symbolic(orig=nil)
      p = Expression[@base.symbolic]
    end
  end

  def initialize
    super()
    @endianness = :big
    @size = 8
  end

  def init_opcode_list
    init_sstic2013
    @opcode_list
  end
end

end # end of module Metasm
