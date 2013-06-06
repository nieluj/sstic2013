CFLAGS = -O3 -march=native -fomit-frame-pointer -Wall -pedantic
LDFLAGS =
CC = gcc
SOURCE_FILES := $(shell ls *.c *.h *.rb)

solve-part3.o: solve-part3.c
	@$(CC) -c $(CFLAGS) -DHOLLYWOOD -fopenmp $< -o $@

solve-part3: solve-part3.o md5.o
	@$(CC) $(CFLAGS) -fopenmp $^ -o $@

%.o: %.c
	@$(CC) -c $(CFLAGS) $< -o $@

%: %.c
	@$(CC) $(CFLAGS) $(LDFLAGS) $< -o $@

solve-sstic2013.tar.bz2: Makefile $(SOURCE_FILES) solve-sstic2013.sh
	[ -d "solve-sstic2013" ] || mkdir solve-sstic2013
	cp -L $^ solve-sstic2013
	tar jcvf $@ solve-sstic2013
	rm -rf solve-sstic2013

archive.tar.gz: dump.bin solve-part1.rb
	@./solve-part1.rb $< > $@

archive_data: archive.tar.gz
	@tar zxOf $< archive/data > $@

atad: archive_data solve-part2
	@./solve-part2 $< > $@

script.ps: atad
	@base64 -d $< > $@

part4.vcard: script.ps solve-part3
	@./solve-part3 $< > $@

email.txt: part4.vcard solve-part4.rb
	@./solve-part4.rb $< > $@

archive: solve-sstic2013.tar.bz2
email: email.txt
clean:
	rm -f solve-part2 solve-part3 *.o archive.tar.gz archive_data atad script.ps part4.vcard email.txt

.PHONY: clean email archive
