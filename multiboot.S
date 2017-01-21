#define MULTIBOOT_MAGIC	(0x1badb002)
#define MULTIBOOT_FLAGS	(3)

.section .multiboot
	/* multiboot header */
	jmp _start
	.align 4
	.long MULTIBOOT_MAGIC
	.long MULTIBOOT_FLAGS
	.long -(MULTIBOOT_MAGIC + MULTIBOOT_FLAGS)

.globl _start
.text
.code32
_start:
	/*
	 * We are left in protected mode by the bootloader.
	 * Next, we need to enter long mode.
	 *
	 * multiboot specifies that at this point:
	 *  - A20 is enabled
	 *  - %eax := 0x2badb002
	 *  - %ebx := address of the multiboot information structure
	 *  - cr0: PG cleared and PE set, rest undefined
	 *  - flags: VM and IF cleared, rest undefined
	 *  - All other registers are undefined (including esp, gdt, idt)
	 */

	/* ensure we were booted with a multiboot bootloader */
	cmpl $0x2badb002, %eax
	jne .Lstart_failed

	/* setup a stack, and try to get the flags in a sane state (cleared) */
	mov $stack_top, %esp
	pushl $0
	popfl

	/*
	 * Next, we are going to try to enter long mode, but
	 * first we will do a sanity check to ensure that we
	 * are infact running on a processor that supports the
	 * System V amd64 ABI.
	 */

	call is_sysv_amd64_supported
	testl %eax, %eax
	jz .Lstart_failed

	/* set GDT */
	lgdt gdt

	/* disable paging */
	movl %cr0, %eax
	andl $~(1 << 31), %eax
	movl %eax, %cr0

	/* setup page table */

	/* enable pae */
	movl %cr4, %eax
	orl $(1 << 5), %eax
	movl %eax, %cr4

	/* enter long mode (compatability mode) */
	mov $0xc0000080, %ecx
        rdmsr
	orl $(1 << 8), %ecx
	wrmsr

	/* set task register and gdt register */

	/* enable paging */
	movl %cr0, %eax
	orl $((1 << 31) | 1), %eax
	mov %eax, %cr0

	/* jump into long mode */
	pushl $_start64
	lret

.Lstart_failed:
	hlt
	jmp .Lstart_failed

	/* int is_extended_cpuid_available(void); */
is_extended_cpuid_available:
	/* save ebx since it is trashed by cpuid */
	pushl %ebx

	/* load the flags register into eax */
	pushfl
	popl %eax

	/* save it for comparison in ecx */
	movl %eax, %ecx

	/* try and flip the cpuid bit and store into the flags register */
	xorl $(1 << 21), %eax
	pushl %eax
	popfl

	/* load the resulting flags register */
	pushfl
	popl %eax

	/* if the cpuid bit was unchanged, then we can't use cpuid! */
	cmpl %eax, %ecx
	je .Lno_cpuid

	/* check basic cpuid */
	xorl %eax, %eax
	cpuid
	cmpl $0x1, %eax
	jb .Lno_cpuid

	/* check extended cpuid */
	movl $0x80000000, %eax
	cpuid
	cmpl $0x80000001, %eax
	jb .Lno_cpuid

	/* extended cpuid supported return eax=1 */
	movl $1, %eax
	popl %ebx
	ret

.Lno_cpuid:
	/* extended cpuid not supported return eax=0 */
	xorl %eax, %eax
	popl %ebx
	ret

	/* int is_sysv_amd64_supported(void); */
is_sysv_amd64_supported:
	/*
	 * The System V AMD64 ABI requires the following features:
	 *  - fpu
	 *  - tsc
	 *  - cx8
	 *  - cmov
	 *  - mmx
	 *  - sse
	 *  - sse2
	 *  - fxsr
	 *  - syscall
	 *  - pae
	 *  - pse
	 *  - msr
	 *  - pge
	 *  - pat
	 *  - clflush
	 */

	/* save ebx since it is trashed by cpuid */
	pushl %ebx

	/* check that we can use extended cpuid */
	call is_extended_cpuid_available
	testl %eax, %eax
	jnz 1f
	popl %ebx
	ret

1:
	/*
	 * First check for the following features using basic cpuid:
	 * - fpu  bit 0
	 * - tsc  bit 4
	 * - cx8  bit 8
	 * - cmov bit 15
	 * - mmx  bit 23
	 * - sse  bit 25
	 * - sse2 bit 26
	 * - fxsr bit 24
	 * - pae  bit 6
	 * - pse  bit 3
	 * - msr  bit 5
	 * - pge  bit 13
	 * - pat  bit 16
	 * - clflush bit 19
	 */
	movl $1, %eax
	cpuid
#define BASIC_CPUID_FEATURES 0x789a179
	andl $BASIC_CPUID_FEATURES, %edx
	cmpl $BASIC_CPUID_FEATURES, %edx
	jne .Lno_long_mode

	/*
	 * Next check for the following features using extended cpuid:
	 * - lm bit 29
	 */
	movl $0x80000001, %eax
	cpuid
#define EXTENDED_CPUID_FEATURES 0x20000000
	andl $EXTENDED_CPUID_FEATURES, %edx
	cmpl $EXTENDED_CPUID_FEATURES, %edx
	jne .Lno_long_mode

	/* cpuid reports our processor supports all the required features */
	movl $1, %eax
	popl %ebx
	ret

.Lno_long_mode:
	/* some feature is missing return eax=0 */
	xorl %eax, %eax
	popl %ebx
	ret

enter_long_mode:
	ret

.code64
_start64:
	.align 4

	/* we have just entered long mode. now: load the embedded elf */

1:
	hlt
	jmp 1b

.bss
	.align 4096
stack_bottom:
	/* create an 8k stack (page aligned) */
	.skip 8192
stack_top:


	/* Page table storage */
pagetable:
	.skip 8192
pagetable_end:

.data
	.align 4

	/* GDT */
gdt:
	.word	gdt_end - gdt
	.long	gdt
	.word	0
	.quad	0x0000000000000000	/* NULL descriptor */
	.quad	0x00af9a000000ffff	/* __KERNEL_CS */
	.quad	0x00cf92000000ffff	/* __KERNEL_DS */
	.quad	0x0080890000000000	/* TS descriptor */
	.quad   0x0000000000000000	/* TS continued */
gdt_end:

	.align 4096
_kernel_start:
	/* include the kernel elf (page aligned) */
	.incbin "kernel.strip"
_kernel_end:

	/* registers
	long mode
	compatability mode

	aesni
	general purpose registers
	rip
	flags register
	gdtr
	idtr
	ldtr
	tr
	control registers
	debug registers
	test registers
	segment registers
	sse/avx
	x87
	amdv
	vtx
	*/

