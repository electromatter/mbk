CC=gcc
LD=ld
CFLAGS=-g -Wall -Wextra -pedantic -Werror -std=c90
LDFLAGS=

OBJS=boot.o early.o

.PHONY: default
default: kernel.elf

%.o: %.c
	$(CC) $(CFLAGS) -o $@ -c $<

%.o: %.S
	$(CC) $(CFLAGS) -o $@ -c $<

kernel.elf: linker.ld $(OBJS)
	$(LD) $(LDFLAGS) -o $@ -T $^

.PHONY: clean
clean:
	@rm -f *.elf
	@rm -f *.o

