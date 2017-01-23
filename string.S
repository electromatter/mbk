#define MULTIBOOT_MAGIC	(0x1badb002)
#define MULTIBOOT_FLAGS	(3)

.section .multiboot
	/* multiboot header */
	jmp _start
	.align 4
	.long MULTIBOOT_MAGIC
	.long MULTIBOOT_FLAGS
	.long -(MULTIBOOT_MAGIC + MULTIBOOT_FLAGS)

.bss
.align 64
	.skip 4096
stack:

.globl _start
.text
.code32
_start:
	movl $stack, %esp
	cld

	subl $0x1000, %esp
	movl %esp, %edi

	call clear_screen

	pushl %edi
	pushl $-100
	call uhex32
	addl $12, %esp

	pushl $0x07
	pushl %edi
	pushl $0
	call strcpy_screen
	addl $12, %esp

	hlt
	jmp _start

	/* void clear_screen(void); */
.set screen_buffer, 0xb8000
.set screen_size, 80*25*2
clear_screen:
	pushl $screen_size
	pushl $0
	pushl $screen_buffer
	call memset
	addl $12, %esp
	ret

	/* int strcpy_screen(int offset, const char *s, int color); */
strcpy_screen:
	pushl %ebp
	movl %esp, %ebp
	pushl %edi
	pushl %esi
	movl 16(%ebp), %ecx
	movl 12(%ebp), %esi
	movl 8(%ebp), %edi
	andl $0xff, %ecx
	shll $8, %ecx
1:
	movzb (%esi), %eax
	test %eax, %eax
	jz 2f
	orl %ecx, %eax
	movw %ax, screen_buffer(, %edi, 2)
	inc %esi
	inc %edi
	jmp 1b
2:
	movl %edi, %eax
	popl %esi
	popl %edi
	popl %ebp
	ret

	/* char *uhex(char *s, unsigned int x); */
uhex:
	pushl %ebp
	movl %esp, %ebp
	pushl %edi
	movl 12(%ebp), %edx
	movl 8(%ebp), %edi
	movl %edx, %eax
	xorl %ecx, %ecx
2:
	addl $4, %ecx
	shrl $4, %eax
	testl %eax, %eax
	jnz 2b
	jmp 1f
uhex32:
	pushl %ebp
	movl %esp, %ebp
	pushl %edi
	movl 12(%ebp), %edx
	movl 8(%ebp), %edi
	movl $32, %ecx
1:
	subl $4, %ecx
	movl %edx, %eax
	shrl %cl, %eax
	andl $0xf, %eax
	movzb .Ltable(%eax), %eax
	movb %al, (%edi)
	incl %edi
	testl %ecx, %ecx
	jnz 1b
	movb $0, (%edi)
	movl 12(%ebp), %edi
	popl %edi
	popl %ebp
	ret
.Ltable:
	.ascii "0123456789abcdef"

	/* char *itoa(int x, char *s, int base); */
itoa:
	pushl %ebp
	movl %esp, %ebp
	pushl %edi
	pushl %esi
	movl 16(%ebp), %ecx
	movl 12(%ebp), %edi
	movl %edi, %esi
	movl 8(%ebp), %eax
	testl $(1 << 31), %eax
	jz 1f
	movb $'-, (%edi)
	incl %edi
	movl %edi, %esi
	negl %eax
	jns 1f
	xorl %eax, %eax
	movl $1, %edx
	jmp 2f
1:
	xorl %edx, %edx
2:
	divl %ecx
	cmpl $10, %edx
	jb 3f
	addl $('a - '0 - 10), %edx
3:
	addl $'0, %edx
	movl %edx, (%edi)
	incl %edi
	testl %eax, %eax
	jnz 1b
	movb $0, (%edi)
4:
	decl %edi
	movzb (%edi), %edx
	movzb (%esi), %eax
	movb %dl, (%esi)
	movb %al, (%edi)
	incl %esi
	cmpl %edi, %esi
	jb 4b
	movl 12(%ebp), %eax
	popl %esi
	popl %edi
	popl %ebp
	ret

	/* size_t strlen(const char *s); */
strlen:
	pushl %ebp
	movl %esp, %ebp
	pushl %edi
	movl 8(%ebp), %edi
	xorl %eax, %eax
	movl $-1, %ecx
	repnz scasb
	notl %ecx
	decl %ecx
	movl %ecx, %eax
	popl %edi
	popl %ebp
	ret

	/* char *strcpy(char *dest, const char *src); */
strcpy:
	pushl %ebp
	movl %esp, %ebp
	pushl %edi
	pushl %esi
	movl 8(%ebp), %ecx
	movl 12(%ebp), %esi
	movl 16(%ebp), %edi
	pushl %edi
	movl $-1, %ecx
	jmp 1f

	/* char *strncpy(char *dest, const char *src, size_t n); */
strncpy:
	pushl %ebp
	movl %esp, %ebp
	pushl %edi
	pushl %esi
	movl 8(%ebp), %ecx
	movl 12(%ebp), %esi
	movl 16(%ebp), %edi
	pushl %edi

1:
	testl %ecx, %ecx
	jz 2f
	movzb (%esi), %eax
	movb %al, (%edi)
	testl %eax, %eax
	jz 2f
	incl %esi
	incl %edi
	decl %ecx
	jmp 1b
2:

	popl %eax
	popl %esi
	popl %edi
	popl %ebp
	ret


	/* char *strcat(char *dest, const char *src); */
strcat:
	pushl %ebp
	movl %esp, %ebp
	pushl %edi
	pushl %esi
	movl 8(%ebp), %esi
	movl 12(%ebp), %edi
	pushl %edi
	movl $-1, %ecx
	jmp 1f
	/* char *strncat(char *dest, const char *src, size_t n); */
strncat:
	pushl %ebp
	movl %esp, %ebp
	pushl %edi
	pushl %esi
	movl 8(%ebp), %ecx
	movl 12(%ebp), %esi
	movl 16(%ebp), %edi
	pushl %edi
1:
	xorl %eax, %eax
	repnz scasb

1:
	testl %ecx, %ecx
	jz 2f
	movzb (%esi), %eax
	movb %al, (%edi)
	testl %eax, %eax
	jz 2f
	incl %esi
	incl %edi
	decl %ecx
	jmp 1b
2:

	popl %eax
	popl %edi
	popl %esi
	popl %edi
	popl %ebp
	ret

	/* void *memmove(void *dest, const void *src, size_t n); */
_memmove:
	pushl %ebp
	movl %esp, %ebp
	pushl %esi
	pushl %edi
	movl 16(%ebp), %ecx
	movl 12(%ebp), %esi
	movl 8(%ebp), %edi

	movl %esi, %eax
	subl %edi, %eax
	cmpl %ecx, %eax
	jbe .Lnon_overlapping

	std
	leal -1(%ecx, %esi), %esi
	leal -1(%ecx, %edi), %edi

.Lnon_overlapping:
	rep movsb
	cld
	movl 16(%ebp), %eax
	popl %edi
	popl %esi
	popl %ebp
	ret

	/* void *memset(void *s, int c, size_t n); */
_memset:
	pushl %ebp
	movl %esp, %ebp
	pushl %edi
	movl 16(%ebp), %ecx
	movl 12(%ebp), %eax
	movl 8(%ebp), %edi
	rep stosb
	movl 12(%ebp), %eax
	popl %edi
	popl %ebp
	ret

.data
.align 4
screen_ptr:
	.word 0
screen_color:
	.word 0

