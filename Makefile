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

%.strip: %.elf
	strip -o $@ $<

kernel.elf: $(OBJS)
	$(CC) $(CFLAGS) -o $@ $^

multiboot: multiboot.S multiboot.ld kernel.strip
	$(CC) $(MULTIBOOT_CFLAGS) -T multiboot.ld -o $@ $<
#	strip $@

.PHONY: clean
clean:
	@rm -f *.elf
	@rm -f *.strip
	@rm -f *.o
	@rm -f multiboot

