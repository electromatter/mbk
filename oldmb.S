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

	/* setup page table */

	/* zero out page table */
	mov $pt_start, %edi
1:
	movl $0, (%edi)
	leal 4(%edi), %edi
	cmpl $pt_end, %edi
	jb 1b

	/* setup page tables for 512g and 1g */
	movl $(pt_1g + 7), %eax
	movl %eax, (pt_512g)
	movl $(pt_2m + 7), %eax
	movl %eax, (pt_1g)

	/* identity map the first 1g using 2m pages */
	movl $pt_2m, %edi
	movl $0x183, %eax
1:
	movl %eax, (%edi)
	addl $(1 << 21), %eax
	leal 8(%edi), %edi
	cmpl $pt_end, %edi
	jb 1b
hlt
	/* enable pae */
	movl %cr4, %eax
	orl $(1 << 5), %eax
	movl %eax, %cr4

	/* enter long mode (compatability mode) */
	mov $0xc0000080, %ecx
        rdmsr
	orl $(1 << 8), %ecx
	wrmsr

	/* set GDT and segment registers */
	lgdt (gdt_pointer)

	/* enable paging and protected mode */
	movl $pt_start, %eax
	movl %eax, %cr3
	movl %cr0, %eax
	orl $((1 << 31) | 1), %eax
	mov %eax, %cr0

	/* jump into long mode */
	//ljmp $8, $_start64

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
	.align 8
_start64:

	/* we have just entered long mode. now: load the embedded elf */
	movq $0x2f592f412f4b2f4f, %rax
	movq %rax, 0xb8000

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
pt_start:
pt_512g:
	.fill 4096, 1, 0
pt_1g:
	.fill 4096, 1, 0
pt_2m:
	.fill 4096, 1, 0
pt_end:

.data
	.align 8

gdt:
	/* Null segment */
.quad 0

	/*
	 * Code segment:
	 * - Granularity (Limit is in units of 4k pages) bit 55
	 * - Long mode bit 53
	 * - Limit (high 4 bits) bits 48:51
	 * - Present bit 47
	 * - Must be one bit 43, 44
	 * - Readable bit 41
	 * - Limit bits 0:15
	 *
	 * Results in a readable and exectuable segment that we can use to jump
	 * into long mode
	 */
.set gdt_code, . - gdt
	.quad (1 << 55) \
	    | (1 << 53) \
	    | (0xf << 48) \
	    | (1 << 47) \
	    | (3 << 43) \
	    | (1 << 41) \
	    | 0xffff

	/*
	 * Data segment:
	 * - Granularity (Limit is in units of 4k pages) bit 55
	 * - Default operand (32 bits) bit 54
	 * - Limit (high 4 bits) bits 48:51
	 * - Present bit 47
	 * - Must be one bit 42
	 * - Writable bit 41
	 * - Limit bits 0:15
	 *
	 * Results in a readable and writable segment
	 */
.set gdt_data, . - gdt
	.quad (1 << 55) \
	    | (1 << 54) \
	    | (0xf << 48) \
	    | (1 << 47) \
	    | (1 << 42) \
	    | (1 << 41) \
	    | 0xffff
	.quad (1 << 47) | (1 << 42) | (1 << 41) | 0xffff
gdt_end:

gdt_pointer:
	/* GDT Pointer */
	.word gdt_end - gdt - 1
	.long gdt
	.long 0

	.align 4096
_kernel_start:
	/* include the kernel elf (page aligned so we can map it) */
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

