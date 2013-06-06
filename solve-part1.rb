#!/usr/bin/env ruby

require 'tempfile'
require 'digest/md5'
require 'base64'
require 'pcap'
require 'openssl'

TCPStream = Struct.new(:sport, :dport, :data)

def reassemble_tcp_streams(packets)
  streams = Hash.new { |h, k| h[k] = {} }

  packets.each do |pkt|
    sport, dport = pkt.sport, pkt.dport
    if pkt.tcp_syn? and not pkt.tcp_ack? then
      s1 = TCPStream.new(sport, dport, "")
      s2 = TCPStream.new(dport, sport, "")
      streams[sport][dport] = s1
      streams[dport][sport] = s2
    else
      if pkt.tcp_data then
        s = streams[sport][dport]
        s.data << pkt.tcp_data
      end
    end
  end

  return streams
end

def process_icmp_packets(packets)
  pkt_info = []
  delta, tos, ttl = [], [], []
  previous_pkt_time = nil

  packets.each do |pkt|
    pkt_time = pkt.time

    if previous_pkt_time then
      delta << (pkt_time - previous_pkt_time).round
    end
    previous_pkt_time = pkt_time

    next if pkt.ip_tos == 0
    tos << pkt.ip_tos
    ttl << pkt.ip_ttl
  end

  (packets.size - 1).times do |i|
    pkt_info << { delta: delta[i], tos: tos[i], ttl: ttl[i] }
  end

  pkt_info
end

def decrypt_file(iv, data, key)
  cipher = OpenSSL::Cipher::Cipher.new("aes-256-cbc")
  cipher.decrypt
  cipher.iv = iv
  cipher.key = key

  result = cipher.update(data)
  result << cipher.final
  result
end

if ARGV.size != 1 then
  $stderr.puts "usage: solve-part1.rb input ( - for stdin)"
  exit(1)
end

tempfile = nil
input = ARGV.first
if input == "-" then
  tempfile = Tempfile.new("sstic-2013-part1")
  tempfile.write $stdin.read
  path = tempfile.path
else
  path = input
end

$stderr.puts "[*] solving part 1"

icmp_packets, tcp_packets = [], []
f = Tempfile.new("sstic-2013-part1")

cap = Pcap::Capture.open_offline(path)
cap.setfilter("icmp or tcp")

cap.each_packet do |pkt|
  case pkt
  when Pcap::TCPPacket  ; tcp_packets << pkt
  when Pcap::ICMPPacket ; icmp_packets << pkt
  else                  ; raise pkt
  end
end

if tempfile then
  tempfile.close
  tempfile.unlink
end

pkt_info = process_icmp_packets(icmp_packets)
tcp_streams = reassemble_tcp_streams(tcp_packets)

iv, target_md5sum, sstic_tar_gz_chiffre = nil, nil, nil
tcp_streams.each do |sport, v|
  v.each do |dport, s|
    if s.data.size > 10000
      sstic_tar_gz_chiffre = Base64.decode64(s.data)
      next
    end

    s.data.each_line do |line|
      case line
      when /^voici l'iv utilise pour AES : (\h+)$/
        iv = $1
        $stderr.puts "[+] iv = #{iv}"
        iv = [ iv ].pack('H*')
      when /^voici le checksum de l'archive pour verifier le dechiffrement : (\h+)$/
        target_md5sum = $1
        $stderr.puts "[+] target md5sum = #{target_md5sum}"
      end
    end
  end
end

delta_to_idx = { 1 => 0, 2 => 1 }
tos_to_idx = { 2 => 0, 4 => 1 }
ttl_to_idx = { 10 => 0, 20 => 1, 30 => 2, 40 => 3 }

%w{ 0 1 }.permutation.each do |m_delta|
  %w{ 0 1 }.permutation.each do |m_tos|
    %w{ 00 10 01 11 }.permutation.each do |m_ttl|

      key1, key2 = "", ""
      pkt_info.each do |info|
        delta = m_delta[ delta_to_idx[ info[:delta] ] ]
        tos = m_tos[ tos_to_idx[ info[:tos] ] ]
        ttl = m_ttl[ ttl_to_idx[ info[:ttl] ] ]
        key1 << delta << tos << ttl
        key2 << delta << ttl << tos
      end

      [ key1, key2 ].each do |k|
        begin
          binkey = k.scan(/.{8,8}/).map {|x| x.to_i(2) }.pack('C*')
          hexkey = binkey.unpack('H*').first
          r = decrypt_file(iv, sstic_tar_gz_chiffre, binkey)
          md5sum = Digest::MD5.hexdigest(r)
          $stderr.puts "[+] md5sum(r) = #{md5sum}"

          if md5sum == target_md5sum then
            $stderr.puts "[!] key = #{hexkey}"
            $stdout.write r
            exit(0)
          else
            $stderr.puts "[-] wrong md5sum"
          end

        rescue OpenSSL::Cipher::CipherError => e
          #$stderr.puts "[-] key = #{hexkey}, error: #{e}"
        end
      end

    end
  end
end
