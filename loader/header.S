.file "multiboot.S"

#define MULTIBOOT_MAGIC	(0x1badb002)
#define MULTIBOOT_FLAGS	(3)

	/* multiboot header */
	.section .multiboot
	.align 16
	.long MULTIBOOT_MAGIC
	.long MULTIBOOT_FLAGS
	.long -(MULTIBOOT_MAGIC + MULTIBOOT_FLAGS)

	.bss
	.align 4096
stack_base:
	.skip 4096
stack:

	.text
	.align 16
	.code32
	.extern load_kernel
	.globl _start
	.type _start, @function

_start:
	/* disable interrupts */
	cli

	/* ensure we were booted with a multiboot complient bootloader */
	cmpl $0x2badb002, %eax
	jne abort

	/* zero out the stack */
	leal stack_base, %edi
	xorl %eax, %eax
	movl $stack - stack_base, %ecx
	cld
	rep stosl

	/* setup base stack */
	leal -64(%edi), %esp
	xorl %ebp, %ebp

	/* clear flags */
	pushl $0
	popfl

	/* compute the loader offset (result in %eax) */
	call get_offset

	/*
	 * Call load_kernel to actually load the kernel
	 *
	 * void load_kernel(void *loader,
	 *		    int loader_size,
	 *		    void *elf,
	 *		    int elf_size,
	 *		    void *info);
	 */
	pushl %ebx
	pushl $elf_size
	leal elf_start(%eax), %ecx
	pushl %ecx
	pushl $loader_size
	leal loader_start(%eax), %ecx
	pushl %ecx
	call load_kernel

	.globl abort
	.type abort, @function
abort:
	hlt
	jmp abort

	.globl get_offset
	.type get_offset, @function
get_offset:
	call 2f
1:
	ret
2:
	movl (%esp), %eax
	subl $1b, %eax
	ret

	.globl check_cpuid
	.type check_cpuid, @function
check_cpuid:
	pushl %ebp
	movl %esp, %ebp
	pushl %ebx

	/* try to flip the cpuid bit in flags */
	pushfl
	popl %eax
	movl %eax, %ecx
	xorl $(1 << 21), %eax
	pushl %eax
	popfl
	pushfl
	popl %eax
	cmpl %eax, %ecx
	je no_cpuid

	/* check basic cpuid */
	movl $0, %eax
	cpuid
	cmpl $1, %eax
	jb no_cpuid

	movl $1, %eax
	cpuid
	movl 8(%ebp), %ecx
	andl %ecx, %eax
	cmpl %ecx, %eax
	jne no_cpuid

	/* check extneded cpuid */
	movl $(1 << 31), %eax
	cpuid
	cmpl $((1 << 31) | 1), %eax
	jb no_cpuid

	movl $((1 << 31) | 1), %eax
	cpuid
	movl 12(%ebp), %ecx
	andl %ecx, %eax
	cmpl %ecx, %eax
	jne no_cpuid

	/* success! */
	xorl %eax, %eax
	popl %ebx
	popl %ebp
	ret

no_cpuid:
	movl $1, %eax
	popl %ebx
	popl %ebp
	ret

	/*
	 * void long_mode_jump(void *identity_page,
	 *		       void *page_table,
	 *		       long long entry_point,
	 *		       long long sp,
	 *		       long long rdi,
	 *		       long long rsi,
	 *		       long long rdx,
	 *		       long long rcx,
	 *		       long long r8,
	 *		       long long r9);
	 */
	.globl long_mode_jump
	.type long_mode_jump, @function
long_mode_jump:

	/*
	 * To enter long mode we need to jump to a segment with LM=1
	 * But, there is no instruction to preform an indirect jump,
	 * so, we will use a return instead.
	 */

	/* compute the absolute address of the trampoline */
	call get_offset
	leal trampoline(%eax), %edx

	/* code segment at offset 8 in the gdt */
	pushl $8
	pushl %edx
	lret

	.code64
trampoline:
	/* identity page */
	movl (%rsp), %eax
	movq %rax, %r10

	/* page table */
	movl 4(%rsp), %eax
	movq %rax, %r14

	addq $8, %rsp

	/* entry point */
	popq %rax

	/* stack */
	popq %rbx

	/* arguments */
	popq %rdi
	popq %rsi
	popq %rdx
	popq %rcx
	popq %r8
	popq %r9

	/* setup the new stack */
	movq %rbx, %rsp
	xorq %rbp, %rbp

	/* copy 1f:2f to the identity page */
	movq %r10, %r12
	leaq 1f(%rip), %r11
	leaq 2f(%rip), %r13
3:
	movb (%r11), %bl
	movb %bl, (%r12)
	incq %r11
	incq %r12
	cmpq %r11, %r13
	jne 3b

	/* prepare to enable paging */
	movq %cr0, %r11
	movq $0x80000001, %rbx
	orq %rbx, %r11

	/* jump to the identity page */
	jmp *%r10

1:
	/* enable paging */
	movq %r14, %cr3
	movq %r11, %cr0
	/* jump to the entry point */
	jmp *%rax
2:

	.data
	.align 4096

elf_start:
	.incbin "kernel.elf"
	.set elf_size, . - elf_start

