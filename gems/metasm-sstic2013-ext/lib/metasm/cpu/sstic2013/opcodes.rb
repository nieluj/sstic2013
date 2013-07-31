require 'metasm/cpu/sstic2013/main'

module Metasm

class Sstic2013

  def addop(name, bin, *args)
    o = Opcode.new name, bin
    args.each { |a|
      o.args << a if @fields_mask[a] or @valid_args[a]
      o.props[a] = true if @valid_props[a]
      o.fields[a] = @fields_shift[a] if @fields_mask[a]
      raise "wtf #{a.inspect}" unless @valid_args[a] or @valid_props[a] or @fields_mask[a]
    }
    @opcode_list << o
  end

  def init_sstic2013
    @opcode_list = []
    @valid_args.update [ :r, :imm, :accu, :mr, :addr ].inject({}) { |h, v| h.update v => true }
    @fields_mask.update :r => 7, :mem_reg => 7, :mem_accu => 0, :imm => 0x7f
    @fields_shift.update :r => 0, :mem_reg => 0, :mem_accu => 0, :imm => 0

    addop 'exit', 0b1100_1000, :stopexec
    addop 'jmpz', 0b1011_1000, :r, :setip
    addop 'shl',  0b1101_1000, :accu
    addop 'not',  0b1010_0000, :accu
    addop 'msb',  0b1110_0000, :accu
    addop 'and',  0b1000_1000, :accu, :r
    addop 'or',   0b1001_0000, :accu, :r
    addop 'mov',  0b0000_0000, :accu, :imm
    addop 'mov',  0b1101_0000, :accu, :mem_accu
    addop 'mov',  0b1100_0000, :mem_reg, :accu
    addop 'mov',  0b1010_1000, :accu, :r
    addop 'mov',  0b1011_0000, :r, :accu
    addop 'jmp',  nil,         :addr, :setip, :stopexec

  end

end # end of class Sstic2013

end # end of module Metasm
