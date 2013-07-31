require 'pp'
require 'readline'
require 'abbrev'
require 'irb'
require 'awesome_print'
#require 'struct'

module IRB

  def self.start_session(binding)
    IRB.setup(nil)

    workspace = WorkSpace.new(binding)

    if @CONF[:SCRIPT]
      irb = Irb.new(workspace, @CONF[:SCRIPT])
    else
      irb = Irb.new(workspace)
    end

    @CONF[:IRB_RC].call(irb.context) if @CONF[:IRB_RC]
    @CONF[:MAIN_CONTEXT] = irb.context

    trap("SIGINT") do
      irb.signal_handle
    end

    catch(:IRB_EXIT) do
      irb.eval_input
    end
  end
end

module Postscript

  DebugContext = Struct.new(:instruction, :stack, :userdict, :systemdict,
                                  :current_array, :current_array_idx, :program_input)

  class Debugger

    KEYWORDS = %w{ trace continue stack break breakpoints step exit show input irb locate }.sort
    KEYWORDS_ABBR = KEYWORDS.abbrev

    Readline.completion_append_character = " "
    Readline.completion_proc = proc { |s| KEYWORDS.grep( /#{Regexp.escape(s)}/ ) }

    attr_accessor :break_next, :breakpoints

    def initialize
      @break_next = false
      @breakpoints = []
      @exit = false
      @do_trace = false
    end

    def debug(ctx)
      @ctx = ctx
      trace if @do_trace
      if break?
        puts "[!] break for #{@ctx.instruction}"
        handle_user_input
      end
    end

    def trace
      #do_locate(5)
      ap @ctx.stack, :multiline => false
      puts "-> #{@ctx.instruction}"
    end

    def break?
      return true if @breakpoints.include?(@ctx.instruction)

      if @break_next then
        @break_next = false
        return true
      end

      return false
    end

    def handle_user_input
      while line = Readline.readline("> ", true)
        case line
        when ""
          do_step
          break
        when /^\s*([^\s]+)\s*(.*)/
          command = KEYWORDS_ABBR[$1] || $1
          args = $2.split(/\s/)
          begin
            ret = send("do_#{command}".to_sym, *args)
            break if ret
            if @exit == true
              return false
            end
          rescue NoMethodError => e
            puts "[!] no command: #{command}"
          end
        else
          puts "[!] wrong command: #{line}"
        end
      end
      return true
    end

    def do_help(*args)
      puts "break object: add a breakpoint for the specified object"
      puts "del object: remove breakpoint for the specified object"
      puts "continue: continue the program execution until next breakpoint"
      puts "step: break at next instruction"
      puts "show (breakpoints|stack|userdict|systemdict): show the specified object"
      puts "trace: enable / disable call tracing"
      puts "irb: spawn irb shell"
      puts "locate count: show position in the current array"
      puts "exit: exit the debugger"
    end

    def do_trace(*args)
      @do_trace = !@do_trace
      if @do_trace then
        puts "[!] trace on"
      else
        puts "[!] trace off"
      end
      return false
    end

    def do_continue(*args)
      return true
    end

    def do_step(*args)
      @break_next = true
      return true
    end

    def do_exit(*args)
      @exit = true
      return false
    end

    def exit?
      @exit
    end

    def do_break(*args)
      unless args.size == 1 then
        puts "[!] break: missing argument"
        return false
      end

      break_object = args.shift.to_sym
      unless @breakpoints.include?(break_object)
        @breakpoints << break_object
      end

      return false
    end

    def do_del(*args)
      unless args.size == 1 then
        puts "[!] break: missing argument"
        return false
      end

      break_object = args.shift.to_sym
      @breakpoints.delete(break_object)

      return false
    end

    def do_breakpoints(*args)
      puts "breakpoints : "
      ap @breakpoints
      return false
    end

    def do_stack(*args)
      ap @ctx.stack
      return false
    end

    def do_userdict(*args)
      ap @ctx.userdict
      return false
    end

    def do_show(*args)
      unless args.size == 1 then
        puts "[!] show: missing argument"
        return false
      end

      obj = args.shift

      case obj
      when /stack/
        return do_stack(*args)
      when /breakpoints/
        return do_breakpoints(*args)
      when /userdict/
        return do_userdict(*args)
      when /systemdict/
        return do_systemdict(*args)
      else
        puts "[!] show: wrong argument #{obj}"
      end

      return false
    end

    def do_irb(*args)
      IRB.start_session(Kernel.binding)
      return false
    end

    def do_locate(*args)
      return false unless @ctx.current_array

      found = false

      count = 10
      if args.size > 0 then
        count = args.shift.to_i
      end
      a = @ctx.current_array[@ctx.current_array_idx, count]
      Postscript::PP.pp_array(a)
      if @ctx.current_array.size > count then
        puts "[...]"
      end
      return false
    end

  end
end # module Postscript
