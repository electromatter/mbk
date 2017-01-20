CC=gcc
LD=ld

CFLAGS=-fPIE -pie -ffreestanding -nostdlib -g \
	-Wall -Wextra -pedantic -Werror -std=c99
MULTIBOOT_CFLAGS=-m32 -ffreestanding -nostdlib -Wall -Wextra -Wextra -pedantic

OBJS=main.o start.o

.PHONY: default
default: multiboot

%.o: %.c
	$(CC) $(CFLAGS) -o $@ -c $<

%.o: %.S
	$(CC) $(CFLAGS) -o $@ -c $<

kernel: $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^

%.strip: %
	strip -o $@ $<

multiboot: multiboot.S multiboot.ld kernel.strip
	$(CC) $(MULTIBOOT_CFLAGS) -T multiboot.ld -o $@ $<
#	strip $@

.PHONY: clean
clean:
	@rm -f *.elf
	@rm -f *.o

