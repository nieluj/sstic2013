require 'stringio'
require 'strscan'
require 'postscript/parser'
require 'postscript/pp'
require 'delegate'
require 'digest/md5'

module Postscript

  class SubArray < Array
    def initialize(parent_array, parent_index, count)
      @parent_array = parent_array
      @parent_index = parent_index
      @array = @parent_array[@parent_index, count]
      super(@array)
    end

    def []=(*args)
      super(*args)

      case args.size
      when 2
        index, value = *args
        @parent_array[@parent_index+index] = value
      when 3
        index, count, value = *args
        @parent_array[@parent_index+index, count] = value
      end
    end
  end

  class SubString < String
    def initialize(parent_string, parent_index, count)
      @parent_string = parent_string
      @parent_index = parent_index
      @string = @parent_string[@parent_index, count]
      super(@string)
    end

    def []=(*args)
      super(*args)

      # Reflect modifications on parent string
      case args.size
      when 2
        index, value = *args
        @parent_string[@parent_index+index] = value
      when 3
        index, count, value = *args
        @parent_string[@parent_index+index, count] = value
      end
    end
  end

  class Filter
    def read
      raise "code me!"
    end
  end

  class SubFileDecodeFilter < Filter
    def initialize(src, eod_mark, eod_count)
      # src must be a strscan object
      @src = src
      @eod_mark = eod_mark
      @eod_count = eod_count
    end

    def read
      r = /#{Regexp.escape(@eod_mark)}/
      s = nil
      while @eod_count >= 0 do
        s = @src.scan_until(r)
        @eod_count -= 1
      end
      # return the string before the eod marker
      s.split[-2]
    end
  end

  class AsciiHexDecodeFilter < Filter
    def initialize(src)
      # src must implement a 'read' method
      @src = src
    end

    def read
      [ @src.read ].pack('H*')
    end
  end

  class InvalidObjectError < StandardError
    def initialize(o)
      @o = o
    end

    def to_s
      "Invalid object: #@o"
    end
  end

  class StackUnderflowError < StandardError
    def initialize(stack, required_count)
      @stack = stack
      @required_count = required_count
    end

    def to_s
      "Stack underflow (required: #{@required_count}): #@stack"
    end
  end

  class Interpreter

    attr_reader :stack, :userdict, :systemdict

    DELIMITERS = "()<>{}/%"

    METHOD_DICT =
    {
      :"]" => "execute_closing_bracket"
    }

    def initialize(filepath, args, debugger = nil)
      reset
      @filepath = filepath
      @parser = Postscript::Parser.new(File.read(@filepath))
      @args = args.dup
      @debugger = debugger
    end

    def reset
      @stack = []
      @userdict = {}
      @systemdict = {}
      @errordict = {}
      @array_stack = []
      @array_idx = {}
      @cvx_count = 0
      @exit = false
    end

    def execute
      @parser.trim_space_or_comments
      while (o = @parser.parse_object) != nil
        execute_object(o)
        @parser.trim_space_or_comments
      end
    end

    def execute_array(a)
      @array_stack << a
      a.each_with_index do |o, i|
        @array_idx[a] = i
        execute_object(o)
      end
      @array_stack.pop
    end

    def execute_object(o)
      if @debugger then
        curr_array = @array_stack.last
        curr_array_idx = @array_idx[curr_array]
        debug_ctx = Postscript::DebugContext.new(o, @stack, @userdict,
            @systemdict, curr_array, curr_array_idx, @parser.input.rest)
        @debugger.debug(debug_ctx)
        if @debugger.exit? then
          exit(0)
        end
      end

      case o
      when Integer, String, Array, TrueClass, FalseClass
        @stack << o
      when Symbol
        if o[0] == "/" then
          @stack << o
        elsif v = ( @systemdict[o] || @userdict[o] )
          case v
          when Array
            execute_array(v)
          else
            @stack << v
          end
        else
          method_name = METHOD_DICT[o] || "execute_#{o}"
          send(method_name)
        end
      else
        raise InvalidObjectError.new(o)
      end
    end

    def execute_currentfile
      @stack << @parser.input
    end

    def execute_pop
      check_args_count(1)

      @stack.pop
    end

    def execute_exch
      check_args_count(2)

      a = @stack.pop
      b = @stack.pop

      @stack << a << b
    end

    def execute_dup
      check_args_count(1)

      a = @stack.last

      @stack << a
    end

    def execute_add
      check_args_count(2)

      b = @stack.pop
      a = @stack.pop

      @stack << (a+b)
    end

    def execute_sub
      check_args_count(2)

      b = @stack.pop
      a = @stack.pop

      @stack << (a-b)
    end

    def execute_def
      check_args_count(2)

      v = @stack.pop
      s = @stack.pop

      unless s.instance_of?(Symbol) and s[0] == "/"
        raise InvalidObjectError.new(s)
      end
      s = s[1..-1].to_sym
      @userdict[s] = v
    end

    def execute_for
      check_args_count(4)

      proc_array = @stack.pop
      limit      = @stack.pop
      increment  = @stack.pop
      initial    = @stack.pop

      return if initial == limit

      if limit > 32768 then
        puts "warning, limit = #{limit} -> 32768"
        limit = 32768
      end

      loop do
        @stack << initial
        execute_array proc_array
        initial += increment
        break if @exit

        if increment > 0 then
          break if initial > limit
        else
          break if initial < limit
        end
      end

      @exit = false
    end

    def execute_index
      check_args_count(1)

      index = @stack.pop

      if @stack.size < index + 1 then
        raise StackUnderflowError.new(@stack, index + 1)
      end
      a = @stack[ @stack.size - index - 1 ]
      @stack << a
    end

    def execute_getinterval
      check_args_count(3)

      count = @stack.pop
      index = @stack.pop
      value = @stack.pop


      if value.size < index + count then
        raise InvalidObjectError.new(value)
      end

      sub_value = nil
      case value
      when Array
        sub_value = SubArray.new(value, index, count)
      when String
        sub_value = SubString.new(value, index, count)
      else
        raise "#{value.class}"
      end

      @stack << sub_value
    end

    def execute_repeat
      check_args_count(2)

      proc_array = @stack.pop
      count      = @stack.pop

      count.times do
        execute_array proc_array
        break if @exit
      end
      @exit = false
    end

    def execute_roll
      check_args_count(2)

      amount = @stack.pop
      count  = @stack.pop

      if @stack.size < count then
        raise StackUnderflowError.new(@stack, count)
      end

      tmp = @stack.pop(count)
      tmp.rotate!(-amount)

      @stack += tmp
    end

    def execute_get
      check_args_count(2)

      index = @stack.pop
      value = @stack.pop

      if value.size < index + 1 then
        raise InvalidObjectError.new(value)
      end

      case value
      when String, SubString
        value = value.bytes.to_a
      end

      tmp = value[index]

      case value
      when String
        tmp = tmp.chr
      end

      @stack << tmp
    end

    def execute_bitshift
      check_args_count(2)

      shift = @stack.pop
      value = @stack.pop

      if shift > 0 then
        value = value << shift
      else
        value = value >> (-shift)
      end

      value = value & 0xffffffff

      @stack << value
    end

    def execute_xor
      check_args_count(2)

      a = @stack.pop
      b = @stack.pop

      @stack << (a ^ b)
    end

    def execute_and
      check_args_count(2)

      a = @stack.pop
      b = @stack.pop

      @stack << (a & b)
    end

    def execute_or
      check_args_count(2)

      a = @stack.pop
      b = @stack.pop

      @stack << (a | b)
    end

    def execute_string
      check_args_count(1)

      len = @stack.pop

      v = Array.new(len, 0).pack('C*')

      @stack << v
    end

    def execute_le
      check_args_count(2)

      a = @stack.pop
      b = @stack.pop

      @stack << ( b <= a )
    end

    def execute_ifelse
      check_args_count(3)

      proc2 = @stack.pop
      proc1 = @stack.pop
      v     = @stack.pop

      if v then
        execute_array proc1
      else
        execute_array proc2
      end
    end

    def execute_length
      check_args_count(2)

       v = @stack.pop

       @stack << v.size
    end

    def execute_mod
      check_args_count(2)

      int2 = @stack.pop
      int1 = @stack.pop

      @stack << (int1 % int2)
    end

    def execute_idiv
      check_args_count(2)

      int2 = @stack.pop
      int1 = @stack.pop

      @stack << (int1 / int2)
    end

    def execute_copy
      check_args_count(1)

      arg1 = @stack.pop

      case arg1
      when Fixnum
        if @stack.size < arg1 then
          raise StackUnderflowError.new(@stack, arg1)
        end

        tmp = @stack.pop(arg1)
        @stack += tmp
        @stack += tmp
      when String
        src = @stack.pop
        arg1[0, src.size] = src
        @stack << SubString.new(arg1, 0, src.size)
      else
        raise "#{arg1}"
      end
    end

    def execute_put
      check_args_count(3)

      value = @stack.pop
      index = @stack.pop
      dest  = @stack.pop

      case dest
      when String
        if dest.size < index + 1 then
          raise InvalidObjectError.new(dest)
        end
        case value
        when Fixnum
          value = value.chr
        end
      end

      dest[index] = value
    end

    def execute_mul
      check_args_count(2)

      int1 = @stack.pop
      int2 = @stack.pop

      @stack << (int1 * int2)
    end

    def execute_forall
      check_args_count(2)

      proc_array = @stack.pop
      v          = @stack.pop

      enum = nil

      case v
      when String
        enum = v.bytes
      else
        enum = v
      end

      enum.each do |o|
        @stack << o
        execute_array proc_array
      end

    end

    def execute_putinterval
      check_args_count(3)

      src   = @stack.pop
      index = @stack.pop
      dest  = @stack.pop

      len = src.size

      dest[index, len] = src
    end

    def execute_mark
      @stack << "-mark-".to_sym
    end

    def execute_closing_bracket
      mark = "-mark-".to_sym
      index = @stack.rindex(mark)
      newarray = @stack[index+1..-1]
      @stack = @stack[0..index-1]
      @stack << newarray
    end

    def execute_calc
      value = @stack.pop
      md5 = Digest::MD5.digest(value)
      @stack << md5
    end

    def execute_filter
      filter_type = @stack.pop
      case filter_type
      when :"/SubFileDecode"
        execute_subfile_decode
      when :"/ASCIIHexDecode"
        execute_asciihex_decode
      when :"/ReusableStreamDecode"
        execute_reusable_stream_decode
      else
        raise "unknown filter: #{filter_type}"
      end
    end

    # FIXME : this method does not work in the general case
    def execute_subfile_decode
      eos_marker = @stack.pop
      eos_count  = @stack.pop
      src        = @stack.pop

      @stack << SubFileDecodeFilter.new(src, eos_marker, eos_count)
    end

    def execute_asciihex_decode
      src = @stack.pop

      @stack << AsciiHexDecodeFilter.new(src)
    end

    def execute_reusable_stream_decode
      src = @stack.pop

      case src
      when String
        @stack << StringIO.new(src)
      when Filter
        @stack << StringIO.new(src.read)
      end
    end

    def execute_bind
      # Do nothing
    end

    def execute_errordict
      @stack << @errordict
    end

    def execute_clear
      @stack = []
    end

    def execute_quit
      exit
    end

    def execute_shellarguments
      @args.each do |arg|
        @stack << arg
      end
      @stack << (@args.size != 0)
    end

    def execute_counttomark
      count = @stack.reverse.index(:"-mark-")
      @stack << count
    end

    def execute_eq
      op1 = @stack.pop
      op2 = @stack.pop

      @stack << (op1 == op2)
    end

    def execute_file
      mode     = @stack.pop
      filename = @stack.pop

      file = nil
      case filename
      when "%stderr"
        file = STDERR
      when "%stdout"
        file = STDOUT
      when "%stdin"
        file = STDIN
      else
        file = File.open(filename, mode)
      end

      @stack << file
    end

    def execute_writestring
      str  = @stack.pop
      file = @stack.pop
      file.write(str)
    end

    def execute_if
      proc_array = @stack.pop
      v          = @stack.pop
      if v then
        execute_array(proc_array)
      end
    end

    def execute_flush
      STDOUT.flush
      STDERR.flush
    end

    def execute_readhexstring
      dst = @stack.pop
      src = @stack.pop

      dst_len = dst.size

      data = src.read(2 * dst_len)
      result = ( data.size == (2 * dst_len) )
      dst[0, dst_len] = [ data ].pack('H*')

      @stack << dst
      @stack << result
    end

    def execute_resetfile
      file = @stack.pop
      file.rewind
    end

    def execute_loop
      proc_array = @stack.pop

      while true
        execute_array proc_array
        break if @exit
      end
      @exit = false
    end

    def execute_readstring
      dst = @stack.pop
      src = @stack.pop

      dst_len = dst.size

      data = src.read(dst_len)
      result = false
      if data then
        result = (data.size == dst_len)
      else
        data = ""
      end

      @stack << data
      @stack << result
    end

    def execute_exit
      @exit = true
    end

    def execute_pstack
      pp @stack
    end

    def execute_cvx
      arg = @stack.pop

      File.open("cvx_#{@cvx_count}.ps", "w") do |f|
        Postscript::PP.pp(arg, 4, f)
      end
      @cvx_count += 1

      parser = Postscript::Parser.new(arg)

      array = parser.parse_objects
      @stack << array
    end

    def execute_exec
      array = @stack.pop
      if array[0..2] == [ 20, :dict, :begin ] then
        #puts "skipping I2"
      else
        execute_array array
      end
    end

    def execute_run
      arg = @stack.pop

      parser = Postscript::Parser.new(File.read(arg))
      array = parser.parse_objects
      execute_array array
    end

    def execute_ne
      op1 = @stack.pop
      op2 = @stack.pop

      @stack << (op1 != op2)
    end

    def execute_closefile
      file = @stack.pop
      file.close
    end

    def execute_rdebug
      # nothing to do
    end

    private
    def check_args_count(n)
      if @stack.size < n then
        raise StackUnderflowError.new(@stack, n)
      end
    end

  end # class Interpreter
end # module Postscript
