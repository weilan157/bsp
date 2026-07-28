# Kernel RT patches (Orange Pi R2S / Ky X1, Linux 6.6.63)

## Upstream

- Official: `patch-6.6.63-rt46.patch.xz`
  - URL: https://cdn.kernel.org/pub/linux/kernel/projects/rt/6.6/older/patch-6.6.63-rt46.patch.xz
  - Downloaded on demand to `dl/` when `KERNEL_RT=y`

Ky/`orange-pi-6.6-ky` already moved unaligned-access probing out of `cpufeature.c`, so these paths from the vanilla RT patch are **skipped** (would reject):

- `arch/riscv/kernel/cpufeature.c`
- `arch/riscv/kernel/smpboot.c`
- `arch/riscv/include/asm/cpufeature.h`
- `arch/riscv/Kconfig` / `thread_info.h` (context differs) → replaced by local patch below

## Local

| File | Purpose |
|------|---------|
| `0001-riscv-enable-PREEMPT_RT-ky.patch` | `ARCH_SUPPORTS_RT` + `HAVE_PREEMPT_AUTO` + `TIF_ARCH_RESCHED_LAZY` |
| `0002-riscv-fix-softirq-own-stack-ifdef-for-RT.patch` | `irq.c` 用 `SOFTIRQ_ON_OWN_STACK`（RT 下避免重定义） |

Applied by `./bsp setup kernel` when `KERNEL_RT=y` (default).
