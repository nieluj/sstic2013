#!/usr/bin/env ruby

require 'open-uri'

HEADER_FILES = Dir["/usr/include/*/asm/unistd_64.h"] +
  Dir["/usr/src/linux*/arch/x86/include/asm/unistd_64.h"]
HEADER_URL = "http://lxr.linux.no/linux+v2.6.37/+save=arch/x86/include/asm/unistd_64.h"

if ARGV.size != 1 then
  $stderr.puts "usage: solve-part4.rb input ( - for stdin)"
  exit(1)
end

data = nil
input = ARGV.first
if input == "-" then
  data = $stdin.read
else
  data = File.read(input)
end

$stderr.puts "[*] solving part 4"

syscalls = nil
data.each_line do |line|
  if line =~ /sys_socketpair/ then
    syscalls = line.chomp.split(':', 2).last.split(/\s+/)
    break
  end
end

headers_data = nil
HEADER_FILES.each do |path|
  if File.exist? path then
    $stderr.puts "[+] found syscall definitions at #{path}"
    headers_data = File.read(path)
    break
  end
end

unless headers_data
  $stderr.puts "[+] downloading syscall definitions from #{HEADER_URL}"
  headers_data = open(HEADER_URL).read
end

b = {}
headers_data.each_line do |line|
  if line =~ /define __NR_([^\s]+)\s+(\d+)/ then
    b["sys_#{$1}"] = $2.to_i
    b["stub_#{$1}"] = $2.to_i
  end
end

a = syscalls.map {|x| b[x]}
raise if a.include? nil

email = a.pack('C*')
$stderr.puts "[!] email: #{email}"
puts email
