# Ky X1 内核配置

基线：`linux-ky-current.config`（orangepi-build 官方全量）。

`./bsp kernel`：复制基线 → 合并 `KERNEL_EXTRA_FRAGMENTS` → `make olddefconfig`。

## 默认 fragment

| 文件 | 作用 |
|------|------|
| `slim.config` | R2S 裁剪显示/无线/音频等；R8125 / YT PHY 打进内核 |
| `rt.config` | `PREEMPT_RT` + `HZ=1000`（需 `KERNEL_RT=y` 且已打补丁） |
| `ethercat.config` | **关闭**内嵌 `CONFIG_ETHERCAT`（改用外置 IgH；需 `KERNEL_ETHERCAT=y`） |

## PREEMPT_RT

默认 `KERNEL_RT=y`：`./bsp setup kernel` / `./bsp kernel` 会：

1. 下载 `patch-6.6.63-rt46.patch.xz` → `dl/`
2. 过滤与 Ky 树冲突的 riscv 文件后打入内核
3. 再打 `vendor/patches/kernel/0001-riscv-enable-PREEMPT_RT-ky.patch`

详情见 `vendor/patches/kernel/README.md`。

关闭实时：

```bash
./bsp config KERNEL_RT=n
./bsp config KERNEL_EXTRA_FRAGMENTS="${PWD}/vendor/kernel-config/slim.config ${PWD}/vendor/kernel-config/ethercat.config"
./bsp setup kernel --update
./bsp kernel --clean
```

## IgH EtherCAT（外置，与 RT 解耦）

默认 `KERNEL_ETHERCAT=y`（**不依赖** `KERNEL_RT`）：

1. 合并 `ethercat.config`（关掉内嵌 EC）
2. 仅打 `0105`（r8125 内置）；清 DTS 内嵌 `ec_master`
3. `./bsp ethercat` 交叉编译官方 `stable-1.6` → `ec_master.ko` + `ec_generic.ko` + CLI

| 硬件 | 接口 | 用途 |
|------|------|------|
| YT8531C ×2 | `eth0` / `eth1` | 普通 IP / DHCP |
| RTL8125BG ×2 | PCIe `enp*` | EtherCAT（`DEVICE_MODULES=generic`） |

板上：`systemctl start ethercat`，`ethercat slaves`，自检 `ethercat-info`。

关闭 EtherCAT：

```bash
./bsp config KERNEL_ETHERCAT=n
./bsp setup kernel --update
./bsp kernel --clean
./bsp rootfs --clean
```

## 板端测试

```bash
sudo rt-latency-test
sudo ethercat-info
sudo systemctl start ethercat
sudo ethercat slaves
```
