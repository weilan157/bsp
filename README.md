# rockchip-bsp

独立仓库：从 GitHub 拉取 `rockchip-linux/u-boot`、`rkbin`、`kernel`，在主机上编译 RK3576 引导链与内核。**不调用 SDK 的 `./build.sh`**。

统一入口：仓库根目录 **`./bsp`**。

泰山派设备树在 `vendor/dts/rockchip/`，构建时复制到 GitHub kernel 树。

## 目录结构

```
rockchip-bsp/
├── bsp                      # 唯一构建入口
├── config.env.example
├── vendor/
│   ├── dts/rockchip/        # 泰山派设备树
│   ├── kernel-config/
│   ├── fit/boot.its         # FIT 打包模板
│   ├── firmware/            # parameter.txt / package-file
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
./bsp config UBOOT_BOARD=rk3576    # 写入 config.env
./bsp uboot --board rk3576 -j 8    # 仅当前命令覆盖
```

无 sudo 且缺 flex/bison：`./bsp env --host-tools`。

### 可选：厂商内核配置

```bash
./bsp config TSPI_VENDOR_KERNEL_CONFIG=y
./bsp kernel
```

默认 `n`，使用 GitHub 官方 defconfig，不启用 PANFROST。

### Debian rootfs

官方 **debootstrap minbase**（无桌面）。产物：

- `out/rootfs/` — 根文件系统目录  
- `out/rootfs.ext4` — 可烧录 rootfs 分区  

默认 Debian 13 (trixie)。主机 debootstrap 过旧时：`./bsp config DEBIAN_RELEASE=bookworm`。

### 从 SDK 刷新设备树

```bash
# config.env
# TSPI_DTS_SOURCE="/path/to/.../dts/rockchip"
./bsp sync dts
./bsp kernel
```

## 编译产物

| 命令 | 产物 |
|------|------|
| `./bsp uboot` | `sources/u-boot/uboot.img`、loader 等 |
| `./bsp kernel` | `out/kernel/Image`、`out/kernel/tspi-3m-rk3576.dtb` |
| `./bsp bootimg` | `out/kernel/resource.img`、`out/boot.img` |
| `./bsp rootfs` | `out/rootfs/`、`out/rootfs.ext4` |
| `./bsp pack --stage-only` | `out/firmware/` |
| `./bsp pack` | `out/update.img` |
| `./bsp all` | 上述全流程 |

分区表见 `vendor/firmware/parameter.txt`。

## 与 SDK 的关系

| 组件 | rockchip-bsp | 泰山派 SDK |
|------|--------------|------------|
| 构建入口 | `./bsp` | `./build.sh` |
| kernel 源码 | GitHub `develop-6.1` | Gitea `rk.kernel-stable` |
| 设备树 | `vendor/dts` → 复制进 kernel | 已在 SDK kernel 内 |
| rootfs | 官方 debootstrap 无桌面 | live-build + 桌面/多媒体 |

## 分支

- `main`：仓库骨架  
- `rk3576`：RK3576 脚本与 vendor 设备树  

## 远程仓库

```bash
git remote add origin git@github.com:weilan157/rockchip-bsp.git
git push -u origin rk3576
```
