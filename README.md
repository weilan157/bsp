# rockchip-bsp — 泰山派 1M（RK3566）

独立仓库：从 GitHub 拉取 `rockchip-linux/u-boot`、`rkbin`、`kernel`，在主机上
编译 **泰山派 1M（LCKFB Taishan Pi 1M，RK3566）** 的引导链、内核、`boot.img`、
Debian rootfs 与 `update.img`。**不调用 SDK 的 `./build.sh`**。

设备树、分区表、defconfig 增量、WiFi/BT 方案均取自泰山派官方 6.1 SDK
（`tspi_1m_linux_kernel6.1_sdk_20260807`，manifest `tspi_1m_rk3566_linux.xml`）。

统一入口：仓库根目录 **`./bsp`**。

## 目录结构

```
rockchip-bsp/
├── bsp                      # 唯一构建入口
├── config.env.example
├── vendor/
│   ├── dts/rockchip/        # SDK 的 tspi-rk3566-*.dts / *.dtsi（7 个文件）
│   ├── kernel-config/       # defconfig fragment（rk3566.config 由内核自带）
│   ├── fit/boot.its         # FIT boot.img 模板（对齐 SDK 的 boot.its）
│   ├── firmware/            # parameter.txt / package-file / ap6212 固件
│   ├── patches/             # u-boot 补丁
│   └── rootfs/              # debootstrap overlay + chroot 配置
├── scripts/
│   ├── lib.sh               # 公共变量与工具函数
│   ├── mod-env.sh
│   ├── mod-sources.sh
│   ├── mod-uboot.sh
│   ├── mod-kernel.sh
│   ├── mod-rootfs.sh
│   └── mod-pack.sh
├── out/                     # 产物（不入库）
└── sources/                 # 克隆的源码（不入库）
```

## 快速开始

```bash
cp config.env.example config.env   # 或 ./bsp config 自动创建
./bsp env                          # 主机依赖（需 sudo）
./bsp setup all                    # 克隆 u-boot / rkbin / kernel
./bsp uboot
./bsp kernel                       # → Image + tspi-rk3566-user-v10-linux.dtb
./bsp bootimg                      # FIT boot.img → out/boot.img
./bsp rootfs                       # Debian minbase → out/rootfs.ext4
./bsp pack                         # out/update.img
```

一键全流程：

```bash
./bsp env
./bsp all                  # 有源码/产物缓存则跳过
./bsp all --clean          # 强制重编
./bsp all --update         # 拉取最新源码（产物仍可复用）
./bsp all --skip-rootfs -j 8
./bsp clean out            # 清除 out/；./bsp clean all 清编译缓存
```

常用命令见 `./bsp help`。配置项：

```bash
./bsp config                       # 列出有效配置
./bsp config KERNEL_DTS_NAME       # 读取
./bsp config UBOOT_BOARD=rk3566    # 写入 config.env
./bsp kernel -j 8                  # 仅当前命令覆盖并行数
```

无 sudo 且缺 flex/bison：`./bsp env --host-tools`。

### 板级相关配置（与 SDK 对齐）

| 配置 | 默认值 | 对应 SDK |
|------|--------|----------|
| `UBOOT_BOARD` | `rk3566` | `./make.sh rk3566`（`RK_UBOOT_SPL=y`） |
| `UBOOT_LOADER_PATTERN` | `rk3566_spl_loader_*.bin` | make.sh `--spl-new` 产物 |
| `KERNEL_DEFCONFIG_FRAGMENTS` | `rk3566.config bsp-boot.config tspi-1m.config` | `rockchip_linux_defconfig` + LCKFB 增量 |
| `KERNEL_DTS_NAME` | `tspi-rk3566-user-v10-linux` | `RK_KERNEL_DTS_NAME` |
| `DTS_FILES_GLOB` | `tspi-rk3566-*` | dts + 6 个 dtsi 一起同步 |
| `parameter.txt` | `vendor/firmware/parameter.txt` | `parameter-buildroot-fit.txt` |

### 内核版本

| | 版本 | 说明 |
|---|---|---|
| 泰山派 SDK | **6.1.141** | `rk/kernel-stable`，tag `linux-6.1-stan-rkr7`，其上 3 个 LCKFB “适配泰山派1M” 提交 |
| 本仓库默认 | **6.1.172** | GitHub `rockchip-linux/kernel` 的 `develop-6.1`，同一 6.1 厂商内核树 |

想用 SDK 里那份内核（含 LCKFB 的 `drivers/net/lte` 等改动）编译时，在 `config.env` 里
指向本机 SDK 的 git 仓库即可（`git clone -b` 支持本地路径）：

```bash
KERNEL_REPO="/path/to/extracted_sdk/.repo/projects/kernel-6.1.git"
KERNEL_BRANCH="tspi-1m-local"
```

### 可选：厂商内核配置

```bash
./bsp config TSPI_VENDOR_KERNEL_CONFIG=y
./bsp kernel
```

默认 `n`；设为 `y` 会再叠加 `vendor/kernel-config/tspi-vendor.config`
（PANFROST / Mali Bifrost / GT9xx）。

### Debian rootfs

官方 **debootstrap minbase**（无桌面）。产物：`out/rootfs/` 与 `out/rootfs.ext4`。
默认 Debian 13 (trixie)；主机 debootstrap 过旧时 `./bsp config DEBIAN_RELEASE=bookworm`。

AP6212A（BCM43438，SDK 同款 `bcmdhd`）：`./bsp rootfs` 会把
`vendor/firmware/ap6212/` 的 `fw_bcm43438a1.bin`、`nvram_ap6212a.txt`、`BCM4343A1.hcd`
装进 `/lib/firmware/`，并启用 `/etc/modules-load.d/bcmdhd.conf`。
改 `overlay/etc/wpa_supplicant/wpa_supplicant.conf` 后 `ifup wlan0`。

### 从 SDK 刷新设备树

```bash
# config.env
TSPI_DTS_SOURCE="/path/to/sdk/kernel/arch/arm64/boot/dts/rockchip"
./bsp sync dts
./bsp kernel
```

`DTS_FILES_GLOB=tspi-rk3566-*` 会把 SDK 的 7 个板级文件一起同步，并在内核
`Makefile` 里补 `dtb-$(CONFIG_ARCH_ROCKCHIP) += tspi-rk3566-user-v10-linux.dtb`。

## 编译产物

| 命令 | 产物 |
|------|------|
| `./bsp uboot` | `sources/u-boot/uboot.img`、`rk3566_spl_loader_*.bin` |
| `./bsp kernel` | `out/kernel/Image`、`out/kernel/tspi-rk3566-user-v10-linux.dtb` |
| `./bsp bootimg` | `out/kernel/resource.img`、`out/boot.img` |
| `./bsp rootfs` | `out/rootfs/`、`out/rootfs.ext4` |
| `./bsp pack --stage-only` | `out/firmware/` |
| `./bsp pack` | `out/update.img` |

分区表与 SDK 一致：`rootfs` 固定 12 GiB、`userdata` 用满剩余空间；
`rootfs` UUID `614e0000-…-54a9` 与 fstab、设备树 bootargs 对应。

## 与 SDK 的对应关系

| 组件 | 泰山派 6.1 SDK | 本仓库 |
|------|----------------|--------|
| 构建入口 | `./build.sh`（device/rockchip） | `./bsp` |
| kernel | `rk/kernel-stable` `linux-6.1-stan-rkr7`（6.1.141）+ LCKFB 提交 | GitHub `rockchip-linux/kernel` `develop-6.1`（6.1.172） |
| u-boot | `android/rk/u-boot`（含 LCKFB `overlay_loader` 补丁） | GitHub `rockchip-linux/u-boot` `next-dev` |
| 设备树 | `tspi-rk3566-user-v10-linux.dts` + 6 dtsi | 逐字复制到 `vendor/dts/rockchip/` |
| 分区表 | `parameter-buildroot-fit.txt` | 逐字复制到 `vendor/firmware/parameter.txt` |
| 内核配置增量 | `rockchip_linux_defconfig` 的 LCKFB 改动 | `vendor/kernel-config/tspi-1m.config` |
| WiFi/BT | bcmdhd + `external/rkwifibt` 固件 | 同（固件放 `vendor/firmware/ap6212/`） |
| rootfs | buildroot / Debian（SDK 自带） | 官方 debootstrap minbase |

**本仓库没有包含**：SDK u-boot 的 `overlay_loader`（`/boot/ubootEnv.txt` 动态
dtbo）、`drivers/net/lte`（RM310 4G 模组驱动）、AVB 签名（SDK 的 `boot.its`
带 `signature` 节点，这里出的是未签名镜像）。

## 分支

- `main`：仓库骨架
- `rk3576`：RK3576 / 泰山派 3M
- `OrangePi-kyX1`：Orange Pi R2S（Ky X1）
- `rk3566`：**本分支**，泰山派 1M RK3566

## 验证状态

- `vendor/dts/rockchip/` 的 7 个文件逐字取自 SDK；已用 `cpp` + `dtc` 对
  GitHub `develop-6.1`（6.1.172）的 dtsi/dt-bindings 预编译通过，仅剩 SDK
  自身写法带来的常规 `simple_bus_reg` / `graph_child_address` 告警。
- `./bsp` 脚本在 Linux 上 `bash -n` 通过；`./bsp sync dts` 实测能同步 7 个文件
  并幂等追加 Makefile 条目。
- u-boot / kernel / rootfs / `update.img` 的完整构建需要 Linux x86_64 主机与
  `aarch64-linux-gnu-` 工具链，未在本次环境里执行；未在真机启动验证。

## 远程仓库

```bash
git remote add origin git@github.com:weilan157/bsp.git
git push -u origin rk3566
```
