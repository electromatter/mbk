#define MULTIBOOT_MAGIC	(0x1badb002)
#define MULTIBOOT_EAX_MAGIC (0x2badb002)
#define LONG_MODE_MAGIC (0x3badb002)
#define MULTIBOOT_FLAGS	(3)

.section .multiboot
	/* multiboot header */
	jmp _start
	.align 16
	.long MULTIBOOT_MAGIC
	.long MULTIBOOT_FLAGS
	.long -(MULTIBOOT_MAGIC + MULTIBOOT_FLAGS)

.data
.align 16
screen_pointer:
	.long 0
multiboot_pointer:
	.long 0

gdt_pointer:
	.word gdt_end - gdt - 1
	.long gdt

map:
	/* gdt */
	.quad gdt
	.quad gdt_end - gdt
	/* page table */
	.quad table
	.quad table_size
	/* kernel elf */
	.quad elf
	.quad elf_end - elf
	/* reserved */
	.quad 0
	.quad 0

gdt:
	/* null segment */
	.quad 0

	/*
	 * code segment:
	 *  - Granuality (bit 23) - limit in units of 4k pages
	 *  - Default Operand Mode (bit 22) - for 32 bit default
	 *  - Long mode (bit 21)
	 *  - Present (bit 15)
	 *  - Must be one (bits 12:11)
	 *  - Readable (bit 9)
	 *  - Segment Limit (bits 19:16 and lower 16 bits)
	 */
.set gdt_code, . - gdt
	.quad ( \
	( \
		( \
		  (1 << 23) | (1 << 22) | (1 << 21) | (0xf << 16) \
		| (1 << 15) | (3 << 11) | (1 << 9) \
		) << 32 \
	) | 0xffff)

	/*
	 * data segment:
	 *  - Granuality (bit 23) - limit in units of 4k pages
	 *  - Default Operand Mode (bit 22) - for 32 bit default
	 *  - Long mode (bit 21)
	 *  - Present (bit 15)
	 *  - Must be one (bits 12:11)
	 *  - Readable (bit 9)
	 *  - Segment Limit (bits 19:16 and lower 16 bits)
	 */
.set gdt_data, . - gdt
	.quad ( \
	( \
		( \
		  (1 << 23) | (1 << 22) | (0xf << 16) \
		| (1 << 15) | (1 << 12) | (1 << 9) \
		) << 32 \
	) | 0xffff)
gdt_end:

.bss
.align 4096
	.skip 4096
stack:

	/* page table for 2m pages for the entire 4g space */
.align 4096
table_root:
	.skip 4096
table_1g:
	.skip 4096
table_2m:
	.skip 4*4096
.set table_size, . - table_root

.globl _start
.text
.code32
.align 16
_start:
	/* clear the flags and setup the stack */
	cli
	cld
	movl $stack, %esp
	xorl %ebp, %ebp
	push %ebp
	push %ebp
	movl %esp, %ebp
	pushl $0
	popfl

	pushl %eax
	call clear_screen

	pushl $.Learly_string
	call puts
	addl $4, %esp

	/* eax preserved for multiboot check */
	popl %eax
	call check_multiboot

	/* setup the environment */
	call check_cpuid
	call setup_paging

	call setup_elf

	/* save the entry point for enter_long_mode */
	pushl %edx
	pushl %eax

	call setup_gdt

	pushl $.Lok_string
	call puts
	addl $4, %esp

	/* enter long mode */
	call enter_long_mode

	pushl $.Ljump_failed_string
	call die

.Learly_string:
	.string "Reached early boot trampoline...\n"
.Lok_string:
	.string "Mapped target elf. Entering long mode...\n"
.Ljump_failed_string:
	.string "Failed to enter long mode!\n"

check_multiboot:
	pushl %ebp
	movl %esp, %ebp

	/* check for the multiboot magic number */
	cmpl $MULTIBOOT_EAX_MAGIC, %eax
	jz 1f
	pushl $.Lmultiboot_fail_string
	call die
1:

	/* save the multiboot info pointer */
	movl %ebx, multiboot_pointer

	popl %ebp
	ret

.Lmultiboot_fail_string:
	.string "Bootloader is not multiboot complient!"

/*
 * Required CPU features:
 *   fpu, tsc, cx8, cmov, mmx, sse, sse2, fxsr, pae, pse, msr, pge, pat,
 *   clflush, lm
 */

#define CPUID_FPU		(1 << 0)
#define CPUID_PSE		(1 << 3)
#define CPUID_TSC		(1 << 4)
#define CPUID_MSR		(1 << 5)
#define CPUID_PAE		(1 << 6)
#define CPUID_CX8		(1 << 8)
#define CPUID_PGE		(1 << 13)
#define CPUID_CMOV		(1 << 15)
#define CPUID_PAT		(1 << 16)
#define CPUID_CLFLUSH		(1 << 19)
#define CPUID_MMX		(1 << 23)
#define CPUID_FXSR		(1 << 24)
#define CPUID_SSE		(1 << 25)
#define CPUID_SSE2		(1 << 26)
#define CPUID_NX		(1 << 20)
#define CPUID_LM		(1 << 29)

#define BASIC_CPUID_FEATURES	( CPUID_FPU	\
				| CPUID_PSE	\
				| CPUID_TSC	\
				| CPUID_MSR	\
				| CPUID_PAE	\
				| CPUID_CX8	\
				| CPUID_PGE	\
				| CPUID_CMOV	\
				| CPUID_PAT	\
				| CPUID_CLFLUSH	\
				| CPUID_MMX	\
				| CPUID_FXSR	\
				| CPUID_SSE	\
				| CPUID_SSE2	\
				)

/* long mode */
#define EXTENDED_CPUID_FEATURES (CPUID_NX | CPUID_LM)

check_cpuid:
	pushl %ebp
	movl %esp, %ebp
	pushl %ebx

	/* try to see if we can flip the cpuid bit in flags */
	pushfl
	popl %eax
	movl %eax, %ecx
	xorl $(1 << 21), %eax
	pushl %eax
	popfl
	pushfl
	popl %eax
	cmpl %eax, %ecx
	jne 1f
	pushl $.Lno_cpuid_string
	call die
1:

	/* check the cpuid support */
	xorl %eax, %eax
	cpuid
	cmpl $1, %eax
	jae 1f
	pushl $.Lno_cpuid_string
	call die
1:

	/* check extended cpuid support */
	movl $(1 << 31), %eax
	cpuid
	cmpl $((1 << 31) | 1), %eax
	jae 1f
	pushl $.Lno_cpuid_string
	call die
1:

	/* check cpu features */
	movl $1, %eax
	cpuid
	andl $BASIC_CPUID_FEATURES, %edx
	cmpl $BASIC_CPUID_FEATURES, %edx
	je 1f
	pushl $.Lno_long_mode_string
	call die
1:

	/* check extended features */
	movl $((1 << 31) | 1), %eax
	cpuid
	andl $EXTENDED_CPUID_FEATURES, %edx
	cmpl $EXTENDED_CPUID_FEATURES, %edx
	je 1f
	pushl $.Lno_long_mode_string
	call die
1:

	popl %ebx
	popl %ebp
	ret

.Lno_cpuid_string:
	.string "CPUID is not supported on this processor!"

.Lno_long_mode_string:
	.string "This CPU does not support the SYSV amd64 ABI!"

setup_paging:
	pushl %ebp
	movl %esp, %ebp

	/* zero out the page table */
	pushl $table_size
	pushl $0
	pushl $table_root
	call memset
	addl $12, %esp

	/* link in the 1g table */
	leal table_1g + 3, %eax
	movl %eax, table_root

	/* link in the 2m tables */
	leal table_2m + 3, %eax
	movl %eax, table_1g
	leal 0x1000 + table_2m + 3, %eax
	movl %eax, 8 + table_1g
	leal 0x2000 + table_2m + 3, %eax
	movl %eax, 16 + table_1g
	leal 0x3000 + table_2m + 3, %eax
	movl %eax, 24 + table_1g

	/* identity map the 2m pages */
	movl $512*4, %ecx
	movl $0x83, %eax
	leal table_2m, %edx
1:
	movl %eax, (%edx)
	addl $0x200000, %eax
	addl $8, %edx
	decl %ecx
	jnz 1b

#define CR0_PG		(1 << 31)
#define CR0_PE		(1)
#define CR4_PAE		(1 << 5)
#define EFER_LM		(1 << 8)
#define EFER_NX		(1 << 11)
#define MSR_EFER	(0xc0000080)

	/* load the page table */
	leal table_root, %eax
	movl %eax, %cr3

	/* enable paging */
	movl %cr4, %eax
	orl $CR4_PAE, %eax
	movl %eax, %cr4

	/* enable long mode */
	movl $MSR_EFER, %ecx
	rdmsr
	orl $EFER_LM | EFER_NX, %eax
	wrmsr

	/* enable page protected mode */
	movl %cr0, %eax
	orl $CR0_PG | CR0_PE, %eax
	movl %eax, %cr0

	popl %ebp
	ret

setup_elf:
	pushl %esi
	pushl %ebp
	movl %esp, %ebp
	xorl %edx, %edx

	leal elf_start, %esi

	/* check that we have a valid header */
	leal elf_end, %ecx
	subl %esi, %ecx
	cmpl $6, %ecx
	jae 1f
	pushl $.Lbad_elf_string
	call die
1:

	/* check elf magic number */
	movl (%esi), %eax
	addl $4, %esi
	cmpl $0x464c457f, %eax
	je 1f
	pushl $.Lbad_elf_string
	call die
1:

	/* elf class edx bit 1: 0 for 32 bits or 1 for 64 bits */
	movzb (%esi), %eax
	addl $1, %esi
	decl %eax
	cmpl $1, %eax
	jbe 1f
	pushl $.Lbad_elf_string
	call die
1:
	shll $1, %eax
	orl %eax, %edx

	/* elf endian edx bit 0: 0 for little or 1 for big */
	movzb (%esi), %eax
	addl $1, %esi
	decl %eax
	cmpl $1, %eax
	jbe 1f
	pushl $.Lbad_elf_string
	call die
1:
	orl %eax, %edx

	/* check that we can proceed */
	testl $2, %edx
	jz 1f
	cmpl $64, %ecx
	jae 2f
	pushl $.Lbad_elf_string
	call die
1:
	cmpl $52, %ecx
	jae 2f
	pushl $.Lbad_elf_string
	call die
2:

	/* elf spec version 1 */
	movzb (%esi), %eax
	addl $1, %esi
	cmpl $1, %eax
	je 1f
	pushl $.Lbad_elf_string
	call die
1:

	/* expect sysv abi (0) */
	movzb (%esi), %eax
	addl $1, %esi
	cmpl $0, %eax
	je 1f
	pushl $.Lbad_elf_string
	call die
1:

	/* ignore abi version */
	addl $8, %esi

	/* type - executable or shared */
	xorl %eax, %eax
	movw (%esi), %ax
	addl $2, %esi
	testl $1, %edx
	jz 1f
	xchgb %al, %ah
1:
	cmpl $2, %eax
	je 2f
	cmpl $3, %eax
	je 2f
	pushl $.Lbad_elf_string
	call die
2:

	/* for amd64 */
	xorl %eax, %eax
	movw (%esi), %ax
	addl $2, %esi
	testl $1, %edx
	jz 1f
	xchgb %al, %ah
1:
	cmpl $0x3e, %eax
	je 2f
	pushl $.Lbad_elf_string
	call die
2:

	/* version again, but this time 32-bits */
	movl (%esi), %eax
	addl $4, %esi
	testl $1, %edx
	jz 1f
	bswapl %eax
1:
	cmpl $1, %eax
	je 2f
	pushl $.Lbad_elf_string
	call die
2:

	/* entry */
	xorl %ecx, %ecx
	movl (%esi), %eax
	addl $4, %esi
	testl $2, %edx
	jz 1f
	movl (%esi), %ecx
	addl $4, %esi
1:
	testl $1, %edx
	jz 2f
	bswapl %eax
	bswapl %ecx
	xchgl %eax, %ecx
2:
	pushl %ecx
	pushl %eax

	/* phoffset */
	xorl %ecx, %ecx
	movl (%esi), %eax
	addl $4, %esi
	testl $2, %edx
	jz 1f
	movl (%esi), %ecx
	addl $4, %esi
1:
	testl $1, %edx
	jz 2f
	bswapl %eax
	bswapl %ecx
	xchgl %eax, %ecx
2:
	pushl %ecx
	pushl %eax

	/* shoffset (ignored) */
	testl $2, %edx
	jz 1f
	addl $4, %esi
1:
	addl $4, %esi

	/* flags = 0 */
	movl (%esi), %eax
	addl $4, %esi
	testl $1, %edx
	jz 1f
	bswapl %eax
1:
	cmpl $0, %eax
	je 2f
	pushl $.Lbad_elf_string
	call die
2:

	/* header size */
	xorl %eax, %eax
	movw (%esi), %ax
	addl $2, %esi
	testl $1, %edx
	jz 1f
	xchgb %al, %ah
1:
	testl $2, %edx
	jnz 2f
	cmpl $52, %eax
	jae 3f
	pushl $.Lbad_elf_string
	call die
2:
	cmpl $64, %eax
	jae 3f
	pushl $.Lbad_elf_string
	call die
3:

	/* phentsize */
	xorl %eax, %eax
	movw (%esi), %ax
	addl $2, %esi
	testl $1, %edx
	jz 1f
	xchgb %al, %ah
1:
	pushl %eax

	/* make sure phentsize makes sense */
	test $2, %edx
	jz 1f
	cmpl $56, %eax
	je 2f
	pushl $.Lbad_elf_string
	call die
1:
	cmpl $32, %eax
	je 2f
	pushl $.Lbad_elf_string
	call die
2:

	/* phnum */
	xorl %eax, %eax
	movw (%esi), %ax
	addl $2, %esi
	testl $1, %edx
	jz 1f
	xchgb %al, %ah
1:
	pushl %eax

	pushl %edx
	pushl $elf_end - elf_start
	pushl $elf_start

	/*
	 * Here the stack looks like:
	 *  pushq entry
	 *  pushq phoffset
	 *  pushl phentsize
	 *  pushl phnum
	 *  pushl %edx (bit 1 for 64 bit elf header, bit 0 for big endian)
	 *  pushl (size of elf)
	 *  pushl (elf base)
	 */
	call map_elf

	/* return entry */
	movl 28(%esp), %eax
	movl 32(%esp), %edx
	popl %esi
	popl %ebp
	ret

.Lbad_elf_string:
	.string "Invalid ELF!"

map_elf:
	pushl %ebp
	movl %esp, %ebp
	pushl %esi
	pushl %edi
	pushl %ebx

	/* load phoffset */
	movl 32(%ebp), %esi
	testl %esi, %esi
	jz 1f
	pushl $.Lbad_elf_string
	call die
1:

	/* load type */
	movl 16(%ebp), %edx
	/* elf size */
	movl 12(%ebp), %edi
	/* elf base */
	movl 8(%ebp), %eax
	/* count (phnum) */
	movl 20(%ebp), %ebx
	/* load phentsize */
	movl 24(%ebp), %ebp
	/* start pointer */
	addl %eax, %esi
	/* end pointer */
	addl %eax, %edi

	testl %ebx, %ebx
	jnz 2f
	pushl $.Lbad_elf_string
	call die

2:
	movl %esi, %eax
	addl %ebp, %esi
	cmpl %esi, %edi
	jae 3f
	pushl $.Lbad_elf_string
	call die
3:

	/* edx */
	movl 28(%esp), %ecx
	movl %ecx, -4(%esp)
	/* elf size */
	movl 24(%esp), %ecx
	movl %ecx, -8(%esp)
	/* elf base */
	movl 20(%esp), %ecx
	movl %ecx, -12(%esp)
	/* program header */
	movl %eax, -16(%esp)
	subl $16, %esp

	call map_section

	addl 16, %esp
	decl %ebx
	jnz 2b

	addl $16, %esp
	popl %ebx
	popl %edi
	popl %esi
	popl %ebp
	ret

map_section:
	pushl %ebp
	movl %esp, %ebp
	pushl %esi
	pushl %ebx

	/* edx (bit 1 for 64 bit pointers, bit 0 for big endian) */
	movl 20(%ebp), %edx

	/* elf size (maximum offset) */
	movl 16(%ebp), %ecx

	/* elf base */
	movl 12(%ebp), %ebx

	/* section header */
	movl 8(%ebp), %esi

	/* map the section described by the section header */
	nop

	popl %ebx
	popl %esi
	popl %ebp
	ret

setup_gdt:
	pushl %ebp
	movl %esp, %ebp

	/* load the gdt so we can jump to long mode */
	lgdtl (gdt_pointer)

	/* select the correct segments */
	movl $gdt_data, %eax
	movw %ax, %ds
	movw %ax, %es
	movw %ax, %ss
	movw %ax, %fs
	movw %ax, %gs

	popl %ebp
	ret

enter_long_mode:
	pushl %ebp
	movl %esp, %ebp

	/*
	 * To enter long mode we need to jump to a segment with LM=1
	 * But, there is no instruction to preform an indirect jump,
	 * so, we will use a return instead.
	 */
	pushl $gdt_code
	pushl $long_mode_trampoline

	/* _start(magic, multiboot); */
	movl $LONG_MODE_MAGIC, %edi
	movl multiboot_pointer, %esi
	leal map, %edx
	leal 8(%ebp), %ecx
	lret

	popl %ebp
	ret

.set screen_buffer, 0xb8000
.set screen_size, 80*25*2
.set line_size, 80
	/* void clear_screen(void); */
clear_screen:
	pushl %ebp
	movl %esp, %ebp
	pushl $screen_size
	pushl $0
	pushl $screen_buffer
	call memset
	addl $12, %esp
	popl %ebp
	ret

	/* int puts(const char *s); */
puts:
	pushl %ebp
	movl %esp, %ebp
	movl 8(%ebp), %eax
	pushl $0x07
	pushl %eax
	call cputs
	addl $8, %esp
	popl %ebp
	ret

	/* int die(const char *s); */
die:
	pushl %ebp
	movl %esp, %ebp
	movl 8(%ebp), %eax
	pushl $0x4f
	pushl %eax
	call cputs
	addl $8, %esp
1:
	cli
	hlt
	jmp 1b

	/*
	 * int cputs(const char *s, int color);
	 *
	 * The color argument is four bits (0xf0) for the background
	 * and four bits (0x0f) for the foreground color.
	 *
	 * If the fourth bit of a color is set, it is "intensified."
	 * Meaning it is brigher than the non-intense color.
	 *
	 * Colors (Intense):
	 *  0	Black (Dark Gray)
	 *  1	Blue (Light Blue)
	 *  2	Green (Light Green)
	 *  3	Cyan (Light Cyan)
	 *  4	Red (Light Red)
	 *  5	Magenta (Light Magenta)
	 *  6	Brown (Yello)
	 *  7   Light Gray (White)
	 */
cputs:
	pushl %ebp
	movl %esp, %ebp
	pushl %edi
	pushl %esi
	pushl %ebx

	/* set color */
	movl 12(%ebp), %ecx
	andl $0xff, %ecx
	shll $8, %ecx

	/* src pointer */
	movl 8(%ebp), %esi

	testl %esi, %esi
	jz .Leof

	/* normalize dest offset */
	movl screen_pointer, %eax
	xorl %edx, %edx
	movl $screen_size, %ebx
	divl %ebx
	movl %edx, %edi
1:
	/* get a character */
	movzb (%esi), %eax
	incl %esi
	testl %eax, %eax
	jz .Leof

	/* handle \r and \n */
	cmpl $'\r, %eax
	je .Llinefloor

	cmpl $'\n, %eax
	je .Llinefeed

	/* write to screen */
	orl %ecx, %eax
	movw %ax, screen_buffer(, %edi, 2)
	incl %edi

	/* normalize dest offset */
	cmpl $screen_size, %edi
	jb 1b

	pushl $(screen_size - line_size)
	pushl $(screen_buffer + line_size)
	pushl $(screen_buffer)
	call memmove

.Llinefloor:
	/* skip back to beginning of line %edi -= %edi % line_size */
	xorl %edx, %edx
	movl %edi, %eax
	movl $line_size, %ebx
	divl %ebx
	subl %edx, %edi
	jmp 1b

.Llinefeed:
	/* move to next line */
	addl $line_size, %edi
	jmp .Llinefloor

.Leof:
	movl %edi, screen_pointer
	xorl %eax, %eax
	popl %ebx
	popl %esi
	popl %edi
	popl %ebp
	ret

	/* void *memmove(void *dest, const void *src, size_t n); */
memmove:
	pushl %ebp
	movl %esp, %ebp
	pushl %esi
	pushl %edi
	pushl %ebx
	movl 16(%ebp), %ecx
	movl 12(%ebp), %esi
	movl 8(%ebp), %edi
	pushl %edi

	testl %ecx, %ecx
	jz .Lempty

	movl %esi, %eax
	subl %edi, %eax
	cmpl %ecx, %eax
	jbe .Lnon_overlapping

	/* overlapping; we must go in reverse */
.Loverlapping:

	movl $3, %ebx
	andl %edi, %ebx
	jz 2f

1:
	decl %esi
	decl %edi
	movzb (%esi), %eax
	movb %al, (%edi)
	decl %ecx
	jz .Lempty
	decl %ebx
	jnz 1b

2:
	movl $0x03, %ebx
	notl %ebx

	/* do words */
3:
	subl $4, %esi
	subl $4, %edi
	movl (%esi), %eax
	movl %eax, (%edi)
	subl $4, %ecx
	jz .Lmemset_end
	test %ebx, %ecx
	jnz 3b

	/* remainder */
4:
	decl %esi
	decl %edi
	movzb (%esi), %eax
	movb %al, (%edi)
	decl %ecx
	jnz 4b

	jmp .Lempty

	/* non-overlapping; we can copy forward */
.Lnon_overlapping:

	movl $3, %ebx
	andl %edi, %ebx
	jz 2f

1:
	movzb (%esi), %eax
	movb %al, (%edi)
	incl %esi
	incl %edi
	decl %ecx
	jz .Lempty
	decl %ebx
	jnz 1b

2:
	movl $0x03, %ebx
	notl %ebx

	/* do words */
3:
	movl (%esi), %eax
	movl %eax, (%edi)
	addl $4, %esi
	addl $4, %edi
	subl $4, %ecx
	jz .Lmemset_end
	test %ebx, %ecx
	jnz 3b

	/* remainder */
4:
	movzb (%esi), %eax
	movb %al, (%edi)
	incl %esi
	incl %edi
	decl %ecx
	jnz 4b

.Lempty:
	popl %eax
	popl %ebx
	popl %edi
	popl %esi
	popl %ebp
	ret

	/* void *memset(void *s, int c, size_t n); */
memset:
	pushl %ebp
	movl %esp, %ebp
	pushl %edi
	pushl %ebx
	movl 16(%ebp), %ecx
	movl 12(%ebp), %eax
	movl 8(%ebp), %edi
	pushl %edi
	testl %ecx, %ecx
	jz .Lmemset_end

	/* %eax = %al:%al:%al:%al */
	andl $0xff, %eax
	movl %eax, %ebx
	shll $8, %ebx
	orl %ebx, %eax
	movl %eax, %ebx
	shll $16, %ebx
	orl %ebx, %eax

	/* align to words */
	movl $3, %ebx
	andl %edi, %ebx
	jz 2f

1:
	movb %al, (%edi)
	incl %edi
	decl %ecx
	jz .Lmemset_end
	decl %ebx
	jnz 1b

2:
	movl $0x03, %ebx
	notl %ebx

	/* do words */
3:
	movl %eax, (%edi)
	addl $4, %edi
	subl $4, %ecx
	jz .Lmemset_end
	test %ebx, %ecx
	jnz 3b

	/* remainder */
4:
	movb %al, (%edi)
	incl %edi
	decl %ecx
	jnz 4b

.Lmemset_end:
	popl %eax
	popl %ebx
	popl %edi
	popl %ebp
	ret

.code64
long_mode_trampoline:
1:
	xorq %rax, %rax
	movl %edi, %eax
	movq %rax, %rdi

	xorq %rax, %rax
	movl %esi, %eax
	movq %rax, %rsi

	xorq %rax, %rax
	movl %edx, %eax
	movq %rax, %rdx

	xorq %rsp, %rsp
	xorq %rbp, %rbp

	xorq %rax, %rax
	movl %ecx, %eax
	jmp *%rax

	hlt
	jmp 1b

.data
	.align 4096
elf_start:
	.incbin "kernel.elf"
elf_end:

