CC=gcc
LD=ld

CFLAGS=-fPIE -pie -ffreestanding -nostdlib -g \
	-Wall -Wextra -pedantic -Werror -std=c99
MULTIBOOT_CFLAGS=-m32 -ffreestanding -nostdlib -Wall -Wextra -Wextra -pedantic

OBJS=main.o start.o

.PHONY: default
default: multiboot.strip

%.o: %.c
	$(CC) $(CFLAGS) -o $@ -c $<

%.o: %.S
	$(CC) $(CFLAGS) -o $@ -c $<

%.strip: %.elf
	strip -o $@ $<
	chmod -x $@

kernel.elf: $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^
	chmod -x $@

multiboot.elf: multiboot.S multiboot.ld kernel.strip
	$(CC) $(MULTIBOOT_CFLAGS) -T multiboot.ld -o $@ $<
	chmod -x $@

.PHONY: clean
clean:
	@rm -f *.elf
	@rm -f *.strip
	@rm -f *.o

