require 'singleton'
require 'strscan'

# http://stackoverflow.com/questions/713559/how-do-i-tokenize-this-string-in-ruby
module Postscript
  class Parser
    #DELIMITERS = "()<>[]{}/%"
    DELIMITERS = "()<>{}/%"

    attr_reader :input
    def initialize(str)
      @input = StringScanner.new(str)
    end

    def parse_object
      o = nil
      %w{ procedure string hexstring number boolean name literal_name }.each do |s|
        method_name = "parse_#{s}"
        o = send(method_name.to_sym)
        break if o != nil
      end
      o
    end

    def parse_objects
      a = []
      trim_space_or_comments
      while (object = parse_object) != nil
        a << object
        trim_space_or_comments
      end
      a
    end

    def parse_procedure
      if @input.scan(/\{/) then
        procedure = parse_objects
        @input.scan(/\}/) or raise "unclosed procedure: #{@input.rest}"
        procedure
      else
        nil
      end
    end

    def parse_number
      if @input.scan(/(\d+)#(\d+)/) then
        base, v = @input.matched.split('#', 2)
        v.to_i(base.to_i)
      elsif @input.scan(/-?\b\d+\b/) then
        @input.matched.to_i
      else
        nil
      end
    end

    def parse_boolean
      if @input.scan(/true/) then
        true
      elsif @input.scan(/false/) then
        false
      else
        nil
      end
    end

    def parse_string
      if @input.scan(/\(/) then
        str = parse_string_content
        @input.scan(/\)/) or raise "unclosed string: #{@input.rest}"
        string_unescape(str)
      else
        nil
      end
    end

    def string_unescape(str)
        str.gsub("\\(", "(").gsub("\\)", ")").gsub("\\n", "\n")
    end

    def parse_hexstring
      if @input.scan(/</) then
        str = @input.scan(/[a-fA-F0-9]*/)
        @input.scan(/>/) or raise "unclosed hex string"
        [ str ].pack('H*')
      else
        nil
      end
    end

    def parse_string_content
      @input.scan(/(\\\)|[^\)])*/) and @input.matched
    end

    def parse_name
      if @input.scan(/[^#{Regexp.escape(DELIMITERS)}\s]+/) then
        @input.matched.to_sym
      else
        nil
      end
    end

    def parse_literal_name
      if @input.scan(/\//) then
        @input.scan(/[^#{Regexp.escape(DELIMITERS)}\s]+/) or raise "invalid literal name"
        return ("/" + @input.matched).to_sym
      else
        nil
      end
    end

    def trim_space
      @input.scan(/\s+/)
    end

    def trim_comments
      while trim_comment
        trim_space
      end
    end

    def trim_comment
      if @input.scan(/%/) then
        @input.scan(/[^\n]*/)
      else
        nil
      end
    end

    def trim_space_or_comments
      trim_space ; trim_comments ; trim_space
    end
  end

end # module Postscript
