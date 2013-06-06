#!/bin/bash
TARGET_MD5="968531851beed222851dbfd59140a395"
URL="http://static.sstic.org/challenge2013/dump.bin"

gem which pcap 1>/dev/null
if [ $? -eq 1 ]
then
    echo "pcap gem not found, please execute: gem install ruby-pcap"
    exit 1
fi

if [ $# -eq 1 ]
then
    path="$1"
else
    path="/tmp/$RANDOM.$RANDOM.dump.bin"
    echo "[+] downloading dump.bin to $path"
    wget --quiet -O "$path" "$URL"
fi

md5=$(md5sum "$path" | cut -d ' ' -f 1)

if [ "x$md5" = "x$TARGET_MD5" ]
then
    echo "[+] correct md5sum for $path"
    make --quiet solve-part2 solve-part3
    ./solve-part1.rb "$path" | tar zOxf - archive/data | ./solve-part2 - | base64 -d | ./solve-part3 - | ./solve-part4.rb - >/dev/null
else
    echo "wrong md5 for path $dump, got $md5, expecting $TARGET_MD5"
    exit 1
fi
