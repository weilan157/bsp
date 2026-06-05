# rockchip-bsp

独立仓库：从 GitHub 拉取 `rockchip-linux/u-boot`、`rkbin`、`kernel`，在主机上编译 RK3576 引导链与内核。**不调用 SDK 的 `./build.sh`**。

泰山派设备树已放在 `vendor/dts/rockchip/`，构建时复制到 GitHub kernel 树。

## 目录结构

```
rockchip-bsp/
├── config.env.example
├── vendor/
│   ├── dts/rockchip/        # 泰山派设备树
│   ├── kernel-config/
│   ├── fit/boot.its         # FIT 打包模板
│   └── rootfs/              # debootstrap overlay + chroot 配置
├── scripts/
│   ├── init-env.sh
│   ├── setup-sources.sh
│   ├── setup-kernel.sh
│   ├── sync-kernel-dts.sh
│   ├── sync-kernel-config.sh
│   ├── build-uboot.sh
│   ├── build-kernel.sh
│   ├── build-bootimg.sh
│   ├── mk-fitimage.sh
│   ├── build-debian-rootfs.sh
│   ├── ch-rootfs.sh
│   └── setup-all.sh
├── out/                     # kernel/、rootfs/、rootfs.ext4（不入库）
└── sources/
```

## 快速开始

### U-Boot

```bash
cp config.env.example config.env
./scripts/init-env.sh
./scripts/setup-sources.sh
./scripts/build-uboot.sh
```

### Kernel（GitHub 官方 + 泰山派 DTS）

```bash
./scripts/setup-kernel.sh      # clone develop-6.1 + 复制 tspi 设备树
./scripts/build-kernel.sh      # Image + dtb
./scripts/build-bootimg.sh     # FIT boot.img（resource.img + boot.img）
```

`out/boot.img` 可烧录 **boot 分区**（与 SDK 的 FIT 结构一致：kernel + dtb + resource，无 ramdisk）。

与 SDK 一致的 GPU/触摸配置（可选）：

```bash
# config.env
TSPI_VENDOR_KERNEL_CONFIG=y
./scripts/build-kernel.sh
```

默认 `TSPI_VENDOR_KERNEL_CONFIG=n`，使用 GitHub 官方 defconfig，不启用 PANFROST。

### Debian 官方无桌面 rootfs

与 SDK 的 `live-build` + 桌面/X/Weston 栈不同，使用 **官方 debootstrap minbase**：

```bash
./scripts/init-env.sh              # 含 debootstrap、qemu-user-static
./scripts/build-debian-rootfs.sh
```

产物：

- `out/rootfs/` — 根文件系统目录  
- `out/rootfs.ext4` — 可烧录 rootfs 分区镜像  

默认 **Debian 13 (trixie)**、`arm64`、无桌面。若主机 debootstrap 过旧，在 `config.env` 将 `DEBIAN_RELEASE=bookworm`。

| 对比 | rockchip-bsp | 泰山派 SDK debian |
|------|--------------|-------------------|
| 基线 | 官方 debootstrap minbase | live-build + linaro 基线 |
| 桌面 | 无 | desktop/xfce/gnome 等 |
| Rockchip 多媒体 | 不含（可自行加 deb） | mpp/gstreamer/chromium 等 |
| overlay | 分区 fstab + by-name | 完整 overlay-firmware 等 |

从 SDK 刷新设备树后再 sync（可选）：

```bash
# config.env 中设置：
# TSPI_DTS_SOURCE="/path/to/TaishanPi-3-Linux/kernel/arch/arm64/boot/dts/rockchip"
./scripts/sync-kernel-dts.sh
./scripts/build-kernel.sh
```

## 编译产物

| 脚本 | 产物 |
|------|------|
| `build-uboot.sh` | `sources/u-boot/uboot.img`、`trust.img`、loader 等 |
| `build-kernel.sh` | `out/kernel/Image`、`out/kernel/tspi-3m-rk3576.dtb` |
| `build-bootimg.sh` | `out/kernel/resource.img`、`out/boot.img`（FIT） |
| `build-debian-rootfs.sh` | `out/rootfs/`、`out/rootfs.ext4` |

## 与 SDK 的关系

| 组件 | rockchip-bsp | 泰山派 SDK |
|------|--------------|------------|
| kernel 源码 | GitHub `develop-6.1` | Gitea `rk.kernel-stable`（6.1.99 快照） |
| 设备树 | `vendor/dts` → 复制进 kernel | 已在 SDK kernel 内 |
| defconfig | 官方 `rockchip_linux_defconfig` + `rk3576.config` | 同基线 + 可选 `tspi-vendor.config` |
| 厂商 GPU 配置 | `TSPI_VENDOR_KERNEL_CONFIG=y` 可选 | SDK 默认含 PANFROST 等 |
| boot.img / recovery | `build-bootimg.sh` → FIT `boot.img` | `./build.sh` |
| rootfs | 官方 debootstrap 无桌面 | SDK live-build + 桌面/多媒体栈 |

GitHub 内核 + 泰山派 DTS **能编出 Image/dtb**，但与 SDK 官方镜像在 **驱动/defconfig 版本** 上可能仍有差异，上板前请自行验证。

## 分支

- `main`：仓库骨架
- `rk3576`：RK3576 脚本与 vendor 设备树

## 远程仓库

```bash
git remote add origin git@github.com:weilan157/rockchip-bsp.git
git push -u origin rk3576
```
