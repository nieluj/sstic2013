require 'singleton'
require 'postscript/parser'

module Postscript

  class PP
    include Singleton

    class << self
      def pp(str, width = 4, io = STDOUT)
        self.instance.pp(str, width, io)
      end

      def pp_array(str, width = 4, io = STDOUT)
        self.instance.pp_array(str, width, io)
      end
    end

    def pp(str, width, io)
      @indent = 0
      @width = width
      @indented = false
      @io = io

      @parser = Postscript::Parser.new(str)

      print_objects
    end

    def pp_array(array, width, io)
      @indent = 0
      @width = width
      @indented = false
      @io = io
      array.each do |o|
        print_object(o)
      end
    end

    def print_objects
      @parser.trim_space_or_comments
      while (o = @parser.parse_object) != nil
        print_object(o)
        @parser.trim_space_or_comments
      end
    end

    def print_object(o)
      case o
      when String
        if o.ascii_only? then
          o = "(" + str_escape(o) + ")"
        else
          o = "<" + o.bytes.map {|b| "%2.2x" % b}.join('') + ">"
        end
        print_str(o)
      when Fixnum, TrueClass, FalseClass
        print_str(o.to_s)
      when Symbol
        if o[0] == "/" then
          print_str(o.to_s)
        else
          puts_str(o.to_s)
        end
        if [ :def, :if, :ifelse, :loop, :for, :forall ].include?(o) then
          @io.puts
        end
      when Array
        if @indented
          @indented = false
          @io.puts
        end
        puts_str("{")

        @indent += 1
        o.each {|x| print_object(x) }
        @indent -= 1

        if @indented
          @indented = false
          @io.puts
        end
        puts_str("}")
      else
        raise "#{o.class}"
      end
    end

    def puts_str(str)
      if @indented then
        @io.print " "
      else
        @io.print (" " * @width * @indent)
      end
      @indented = false
      @io.puts str
    end

    def print_str(str)
      if @indented
        @io.print " "
      else
        @io.print (" " * @width * @indent)
        @indented = true
      end
      @io.print str
    end

    def str_escape(str)
      str.gsub("\n", "\\n").gsub("\r", "\\r")
    end

  end

end # module Postscript
