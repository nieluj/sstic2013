require 'metasm/cpu/sstic2013/opcodes'
require 'metasm/parse'

module Metasm

class Sstic2013

  def parse_arg_valid?(op, sym, arg)
    true
  end

  def parse_argument(pgm)
    pgm.skip_space
    return if not tok = pgm.nexttok

    arg = nil
    if tok.type == :string and Reg.s_to_i[tok.raw]
      pgm.readtok
      arg = Reg.new Reg.s_to_i[tok.raw]
    elsif tok.type == :string and tok.raw == "accu"
      pgm.readtok
      arg = Accu.new
    else
      arg = Expression.parse pgm
    end
    arg
  end
end

end # end of module Metasm

