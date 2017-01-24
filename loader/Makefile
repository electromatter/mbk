CFLAGS=-m32 -Wall -Wextra -pedantic -std=c90 -fpic -fpie -fPIC -static -nostdlib -ffreestanding -no-pie
LDFLAGS=-m32 -Wall -Wextra -pedantic -std=c90 -fpic -fpie -fPIC -static -nostdlib -ffreestanding -no-pie

OBJS=header.o loader.o

loader: kernel.elf loader.ld $(OBJS)
	$(CC) $(LDFLAGS) -T loader.ld -o $@ $(OBJS)

%.o: %.S
	$(CC) $(CFLAGS) -o $@ -c $<

%.o: %.c
	$(CC) $(CFLAGS) -o $@ -c $<

