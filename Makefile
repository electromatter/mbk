CC=gcc
LD=ld
MAKE=make

.PHONY: all
all: loader

loader:
	$(MAKE) -C loader

kernel:
	$(MAKE) -C kernel

.PHONY: clean
clean:
	find -name \*.elf -exec rm {} \;
	find -name \*.sym -exec rm {} \;
	find -name \*.o -exec rm {} \;

