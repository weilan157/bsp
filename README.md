# rockchip-bsp — 泰山派 RK3566

独立仓库：从 GitHub 拉取 `rockchip-linux/u-boot`、`rkbin`、`kernel`，在主机上
编译 **泰山派（LCKFB Taishan Pi）RK3566** 的引导链、内核、`boot.img`、Debian
rootfs 与 `update.img`。**不调用 SDK 的 `./build.sh`**。

统一入口：仓库根目录 **`./bsp`**。

## 目录结构

```
rockchip-bsp/
├── bsp                      # 唯一构建入口
├── config.env.example
├── vendor/
│   ├── dts/rockchip/        # 泰山派 RK3566 设备树（rk3566-lckfb-tspi.dts）
│   ├── kernel-config/       # defconfig fragment（rk3566.config 由内核自带）
│   ├── fit/boot.its         # FIT boot.img 模板
│   ├── firmware/            # parameter.txt / package-file
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
./bsp kernel
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
./bsp config UBOOT_BOARD           # 读取
./bsp config UBOOT_BOARD=rk3566    # 写入 config.env
./bsp uboot --board rk3566 -j 8    # 仅当前命令覆盖
```

无 sudo 且缺 flex/bison：`./bsp env --host-tools`。

### RK3566 相关的几个配置项

| 配置 | 默认值 | 说明 |
|------|--------|------|
| `UBOOT_BOARD` | `rk3566` | `./make.sh` 的 board 名 |
| `UBOOT_LOADER_PATTERN` | `rk3566_spl_loader_*.bin` | loader 产物名；RK3566 没有 idblock |
| `KERNEL_DEFCONFIG_FRAGMENTS` | `rk3566.config bsp-boot.config bsp-wifi.config` | 叠加在内核 defconfig 上 |
| `KERNEL_DTS_NAME` | `rk3566-lckfb-tspi` | 编译的 dtb 名 |

### 可选：厂商内核配置

```bash
./bsp config TSPI_VENDOR_KERNEL_CONFIG=y
./bsp kernel
```

默认 `n`，使用 GitHub 官方 defconfig + `rk3566.config`。设为 `y` 会再叠加
`vendor/kernel-config/tspi-vendor.config`（PANFROST / Mali Bifrost / GT9xx）。

### Debian rootfs

官方 **debootstrap minbase**（无桌面）。产物：

- `out/rootfs/` — 根文件系统目录
- `out/rootfs.ext4` — 可烧录 rootfs 分区

默认 Debian 13 (trixie)。主机 debootstrap 过旧时：`./bsp config DEBIAN_RELEASE=bookworm`。

AP6212（BCM43438）：内核走 `brcmfmac`，rootfs 会装 `firmware-brcm80211` + `bluez`，
开机由 `/etc/modules-load.d/brcmfmac.conf` 加载。改
`overlay/etc/wpa_supplicant/wpa_supplicant.conf` 后 `ifup wlan0`。
若扫描不到 AP，需补板级 NVRAM `brcmfmac43430-sdio.txt`。

### 从 SDK 刷新设备树

```bash
# config.env
# TSPI_DTS_SOURCE="/path/to/.../dts/rockchip"
# DTS_EXTRA_FILES="rk3566-linux.dtsi"
./bsp sync dts
./bsp kernel
```

注意 SDK 是 5.10 内核，dts 依赖其 dtsi/驱动，覆盖前先对比 `vendor/dts/README.md` 的说明。

## 编译产物

| 命令 | 产物 |
|------|------|
| `./bsp uboot` | `sources/u-boot/uboot.img`、`rk3566_spl_loader_*.bin` |
| `./bsp kernel` | `out/kernel/Image`、`out/kernel/rk3566-lckfb-tspi.dtb` |
| `./bsp bootimg` | `out/kernel/resource.img`、`out/boot.img` |
| `./bsp rootfs` | `out/rootfs/`、`out/rootfs.ext4` |
| `./bsp pack --stage-only` | `out/firmware/` |
| `./bsp pack` | `out/update.img` |
| `./bsp all` | 上述全流程 |

分区表见 `vendor/firmware/parameter.txt`（Rockchip RK356x 通用 GPT 布局，
`rootfs` UUID `614e0000-…-54a9` 与 fstab、设备树 bootargs 一致）。

## 与 SDK 的关系

| 组件 | rockchip-bsp | 泰山派 SDK |
|------|--------------|------------|
| 构建入口 | `./bsp` | `./build.sh` |
| kernel 源码 | GitHub `develop-6.1` | 泰山派 5.10 内核 |
| 设备树 | `vendor/dts` → 复制进 kernel | 已在 SDK kernel 内 |
| rootfs | 官方 debootstrap 无桌面 | live-build + 桌面/多媒体 |

## 分支

- `main`：仓库骨架
- `rk3576`：RK3576 / 泰山派 3M 脚本与 vendor 设备树
- `OrangePi-kyX1`：Orange Pi R2S（Ky X1）
- `rk3566`：**本分支**，泰山派 RK3566

## 验证状态

- `rk3566-lckfb-tspi.dts` 已用 `dtc` 对 `develop-6.1` 的 dtsi 与 dt-bindings
  预编译通过（`cpp` + `dtc -I dts -O dtb`，无本文件相关告警）。
- u-boot / kernel / rootfs / `update.img` 的完整构建需要 Linux x86_64 主机与
  `aarch64-linux-gnu-` 工具链，未在本仓库的 Windows 工作区里执行。
- 未在真机上启动验证。首次上板请优先确认串口（`ttyS2` / `ttyFIQ0`）、eMMC/SD
  与 HDMI；外设（MIPI 屏、CSI、CAN 等）本分支未提供，见 `vendor/dts/README.md`。

## 远程仓库

```bash
git remote add origin git@github.com:weilan157/bsp.git
git push -u origin rk3566
```
