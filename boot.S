.set ALIGN,    1<<0             # align loaded modules on page boundaries
.set MEMINFO,  1<<1             # provide memory map
.set FLAGS,    ALIGN | MEMINFO  # this is the Multiboot 'flag' field
.set MAGIC,    0x1BADB002       # 'magic number' lets bootloader find the header
.set CHECKSUM, -(MAGIC + FLAGS) # checksum of above, to prove we are multiboot

.section .multiboot
.align 4
.long MAGIC
.long FLAGS
.long CHECKSUM

.section .bss
.align 16
stack_bottom:
.skip 16384 # 16 KiB
stack_top:

.section .text
.global _start
.type _start, @function
_start:

.globl _start32
.code32
.text
_start32:
_start:
	.align 4
	jmp entry

multiboot_header:
	.long MAGIC
	.long FLAGS
	.long CHECKSUM
	.long multiboot_header
	.long _start
	.long _edata
	.long _end
	.long entry

entry:
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
	jne .Lstart32_failed

	/* setup a stack, and try to get the flags in a sane state (cleared) */
	mov $boot_stack_top, %esp
	pushl $0
	popfl
	cld

	/*
	 * Next, we are going to try to enter long mode, but
	 * first we will do a sanity check to ensure that we
	 * are infact running on a processor that supports the
	 * System V amd64 ABI.
	 *
	 * The ABI requires the following features:
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

	/* first, check that cpuid is available */
	call cpuid_available
	test %eax, %eax
	jz .Lstart32_failed

1:
	hlt
	jmp 1b

.Lstart32_failed:
	hlt
	jmp .Lstart32_failed

	/* int cpuid_available(void); */
cpuid_available:
	/* load the flags register into eax */
	pushfl
	popl %eax

	/* save it for comparison in ecx */
	movl %eax, %ecx

	/* try and flip the cpuid bit and store into the flags register */
	xorl (1 << 21), %eax
	pushl %eax
	popfl

	/* load the resulting flags register */
	pushfl
	pop %eax

	/* if the cpuid bit was unchanged, then we can't use cpuid! */
	cmpl %eax, %ecx
	je .Lno_cpuid

	movl $1, %eax
	ret

.Lno_cpuid:
	xorl %eax, %eax
	ret

.code64
_start64:
	.align 16

	/* we have just entered long mode */

1:
	hlt
	jmp 1b

.section .boot_stack
	.skip 16*1024
boot_stack_top:

