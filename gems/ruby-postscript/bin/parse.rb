#!/usr/bin/env ruby
# encoding: utf-8

$LOAD_PATH << File.join(File.dirname(__FILE__), '..', 'lib')

require 'pp'
require 'postscript'

input_file = ARGV.shift

parse_result = Postscript::Parser.parse_file(input_file)

pp parse_result
