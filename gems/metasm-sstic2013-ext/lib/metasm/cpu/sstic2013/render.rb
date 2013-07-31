require 'metasm/cpu/sstic2013/opcodes'
require 'metasm/render'

module Metasm

class Sstic2013

  class Reg
    include Renderable
    def render ; [self.class.i_to_s[@i]] ; end
  end

  class Accu
    include Renderable
    def render ; [ "accu" ] ; end
  end

  def render_instruction(i)
    r = []
    #case i.opname
    #when /^mov/
    #  r << "mov"
    #else
    #  r << i.opname
    #end
    r << i.opname
    if not i.args.empty?
      r << ' '
      i.args.each { |a_| r << a_ << ', ' }
      r.pop
    end
    r
  end

  class Memref
    include Renderable
    def render ; [ "[", @base, "]" ] ; end
  end

end # end of class Sstic2013

end # end of module Metasm
