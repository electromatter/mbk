
# create multiboot image from loader and kernel

.PHONY: clean
clean:
	find -name \*.elf -exec rm {} \;
	find -name \*.sym -exec rm {} \;
	find -name \*.o -exec rm {} \;
	find -name \*.a -exec rm {} \;
	find -name \*.so -exec rm {} \;

CFLAGS=-m32 -Wall -Wextra -pedantic -std=c90 -nostdlib -ffreestanding -no-pie

