
#include <stdint.h>
#include <stddef.h>

extern void
abort(void);

extern void
long_mode_jump(void *identity_page,
	       void *page_table,
	       uint64_t entry_point,
	       uint64_t sp,
	       uint64_t rdi,
	       uint64_t rsi,
	       uint64_t rdx,
	       uint64_t rcx,
	       uint64_t r8,
	       uint64_t r9);

extern int
check_cpuid(uint32_t basic, uint32_t extended);

void *
memset(void *m, int c, size_t n)
{
	uint8_t *dest = m;

	while (n-- > 0)
		*dest++ = (uint8_t)c;

	return m;
}

void *
memmove(void *d, const void *s, size_t n)
{
	uint8_t *dest = d;
	const uint8_t *src = s;

	if (d == s)
		return d;

	if (src < dest && (size_t)(dest - src) < n) {
		/* src and dest are overlapping! We must go in reverse. */
		dest += n;
		src += n;

		while (n-- > 0)
			*--dest = *--src;

		return d;
	}

	/* otherwise memcpy is safe */
	while (n-- > 0)
		*dest++ = *src++;

	return d;
}

struct mem_map {
	int unused;
};

struct multiboot_info {
	int unused;
};

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
#define CPUID_LM		(1 << 29)

#define BASIC_FEATURES		( CPUID_FPU	\
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
#define EXTENDED_FEATURES (CPUID_LM)

void
load_kernel(void *loader,
	    int loader_size,
	    void *elf,
	    int elf_size,
	    void *info)
{
	struct mem_map *map;
	uint64_t entry, stack;

	/* ensure that this processor supports long mode */
	if (check_cpuid(BASIC_FEATURES, EXTENDED_FEATURES))
		abort();

#if 0
	/* setup the memory map */
	if (detect_memory_map(&map, multiboot_info))
		abort();

	/* reserve the loader  */
	if (reserve_loader(map, loader, loader_size))
		abort();

	/* setup gdt */
	if (set_gdt(map))
		abort();

	/* enable pae and longmode */
	if (enable_long_mode())
		abort();

	/* setup paging */
	if (build_pagetable(map))
		abort();

	/* load the kernel */
	if (load_elf(map, &entry, &stack, elf, elf_size))
		abort();

	/* enter the kernel */
	long_mode_jump(NULL, NULL, entry, stack, 0, 0, 0, 0, 0, 0);
#endif
}

