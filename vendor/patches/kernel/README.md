# Kernel patches (Orange Pi R2S / Ky X1, Linux 6.6.63)

## Upstream RT

- Official: `patch-6.6.63-rt46.patch.xz`
  - URL: https://cdn.kernel.org/pub/linux/kernel/projects/rt/6.6/older/patch-6.6.63-rt46.patch.xz
  - Downloaded on demand to `dl/` when `KERNEL_RT=y`

Ky/`orange-pi-6.6-ky` already moved unaligned-access probing out of `cpufeature.c`, so these paths from the vanilla RT patch are **skipped** (would reject):

- `arch/riscv/kernel/cpufeature.c`
- `arch/riscv/kernel/smpboot.c`
- `arch/riscv/include/asm/cpufeature.h`
- `arch/riscv/Kconfig` / `thread_info.h` (context differs) → replaced by local patch below

## Local RT

| File | Purpose |
|------|---------|
| `0001-riscv-enable-PREEMPT_RT-ky.patch` | `ARCH_SUPPORTS_RT` + `HAVE_PREEMPT_AUTO` + `TIF_ARCH_RESCHED_LAZY` |
| `0002-riscv-fix-softirq-own-stack-ifdef-for-RT.patch` | `irq.c` 用 `SOFTIRQ_ON_OWN_STACK`（RT 下避免重定义） |

Applied by `./bsp setup kernel` when `KERNEL_RT=y` (default).

## IgH EtherCAT（外置）

主站改为官方外置模块（`sources/ethercat`，`stable-1.6` + `ec_generic`），**与 `KERNEL_RT` 无关**。

| File | Purpose | Applied? |
|------|---------|----------|
| `0100`–`0104` | 旧内嵌 EC（DTS / EC_GENERIC 过滤等） | **否**（保留作历史参考） |
| `0105-r8125-honor-config-builtin.patch` | r8125 Makefile 尊重 `CONFIG_R8125=y` | **是**（`KERNEL_ETHERCAT=y`） |

`ethercat.config` 显式关闭内核内嵌 `CONFIG_ETHERCAT`；setup 时会清掉 DTS 里旧的 `ec_master` / `ec-mac-*` 节点。

**拓扑（R2S）**：

| 硬件 | 接口 | 用途 |
|------|------|------|
| YT8531C ×2 | SoC GMAC `eth0`/`eth1` | 普通 IP / DHCP |
| RTL8125BG ×2 | PCIe `enp*` | EtherCAT（外置 `ec_generic`） |

构建：`./bsp ethercat`（内核之后）。板上：`systemctl start ethercat` / `ethercat slaves`。
