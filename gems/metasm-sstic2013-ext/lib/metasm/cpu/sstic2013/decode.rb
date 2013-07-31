require 'metasm/cpu/sstic2013/opcodes'
require 'metasm/decode'

module Metasm

class Sstic2013
  def build_opcode_bin_mask(op)
    op.bin_mask = 0
    op.fields.each { |f, off|
      op.bin_mask |= (@fields_mask[f] << off)
    }
    op.bin_mask ^= 0xff
  end

  def build_bin_lookaside
    # sets up a 5 bits value => list of opcodes that may match
    # opcode.bin_mask is built here
    lookaside = Array.new(32) { [] }
    opcode_list.each { |op|
      next unless op.bin
      build_opcode_bin_mask op
      b   = (op.bin >> 3) & 31
      msk = (op.bin_mask >> 3) & 31
      for i in b..(b | (31^msk))
        if i & msk == b & msk then
          lookaside[i] << op
        end
      end
    }
    lookaside
  end

  def decode_findopcode(edata)
    di = DecodedInstruction.new self
    return if edata.ptr+1 > edata.length
    bin = edata.decode_imm(:u8, @endianness)
    edata.ptr -= 1
    @bin_lookaside[(bin >> 3) & 31].each do |op|
      if bin & op.bin_mask == op.bin & op.bin_mask then
        di.opcode = op
        return di
      end
    end
    return nil
  end

  def decode_instr_op(edata, di)
    before_ptr = edata.ptr
    op = di.opcode
    di.instruction.opname = op.name
    bin = edata.decode_imm(:u8, @endianness)

    field_val = lambda { |f|
      if off = op.fields[f]
        (bin >> off) & @fields_mask[f]
      end
    }

    op.args.each { |a|
      di.instruction.args << case a
      when :accu; Accu.new
      when :imm; Expression[field_val[a]]
      when :r; Reg.new(field_val[a])
      when :mem_accu; Memref.new( Accu.new )
      when :mem_reg; Memref.new( Reg.new(field_val[a]) )
      else
        raise SyntaxError, "Internal error: invalid argument #{a} in #{op.name}"
      end
    }

    di.bin_length += edata.ptr - before_ptr

    di
  rescue InvalidRD
  end

  # hash opcode_name => lambda { |dasm, di, *symbolic_args| instr_binding }
  def backtrace_binding
    @backtrace_binding ||= init_backtrace_binding
  end
  def backtrace_binding=(b) @backtrace_binding = b end

  def init_backtrace_binding
    @backtrace_binding ||= {}
    mask = 0xff

    opcode_list.map { |ol| ol.basename }.uniq.sort.each { |op|
      binding = case op
                when /^mov/
                  lambda { |di, a0, a1|
                    { a0 => Expression[a1].reduce }
                  }
                when 'not'
                  lambda { |di, a0| { a0 => Expression[a0, :^, mask] } }
                when 'and', 'or'
                  lambda { |di, a0, a1|
                    e_op = { 'and' => :&, 'or' => :| }[op]
                    ret = Expression[a0, e_op, a1]
                    ret = Expression[ret.reduce]
                    { a0 => ret }
                  }
                when 'msb'
                  lambda { |di, a0|
                    ret = Expression[1<<7, :|, a0]
                    ret = Expression[ret.reduce]
                    { a0 => ret }
                  }
                when 'shl'
                  lambda { |di, a0|
                    ret = Expression[1, :<<, a0]
                    ret = Expression[ret.reduce]
                    { a0 => ret }
                  }
                when 'jmpz', 'jmp', 'exit'
                  lambda { |di, *a| {} }
                end
      @backtrace_binding[op] ||= binding if binding
    }
    @backtrace_binding
  end

  def get_backtrace_binding(di)
    a = di.instruction.args.map { |arg|
      case arg
      when Reg; arg.symbolic(di)
      when Accu; arg.symbolic(di)
      else arg
      end
    }

    if binding = backtrace_binding[di.opcode.basename]
      bd = {}
      bd.update binding[di, *a]
    else
      puts "unhandled instruction to backtrace: #{di}"
      # assume nothing except the 1st arg is modified
      case a[0]
      when Indirection, Symbol; { a[0] => Expression::Unknown }
      when Expression; (x = a[0].externals.first) ? { x => Expression::Unknown } : {}
      else {}
      end.update(:incomplete_binding => Expression[1])
    end
  end

  def get_xrefs_x(dasm, di)
    return [] if not di.opcode.props[:setip]
    case tg = di.instruction.args.first
    when Reg; [Expression[tg.symbolic(di)]]
    when Expression, ::Integer; [ Expression[tg] ]
    else
      puts "unhandled setip at #{di.address} #{di.instruction} (#{tg.class})"
      []
    end
  end

end # end of class Sstic2013

end # end of Module Metasm
