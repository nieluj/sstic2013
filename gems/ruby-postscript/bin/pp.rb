#!/usr/bin/env ruby
# encoding: utf-8

$LOAD_PATH << File.join(File.dirname(__FILE__), '..', 'lib')

require 'postscript'

input_file = ARGV.shift

Postscript::PP.pp(File.read(input_file))
