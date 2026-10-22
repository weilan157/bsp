# Cubie A7Z（Allwinner A733 / sun60iw2p1）

结构与 `rk3566` 分支一致：**官方 u-boot + 官方内核 + 自定义裁剪 rootfs + 板级设备树**，
镜像按板厂给的分区表打包。

## 上游（都是官方仓库）

| 组件 | 仓库/分支 | 说明 |
|---|---|---|
| u-boot | `radxa/u-boot` @ `cubie-aiot-v1.4.6` | Allwinner u-boot 2018.07 + boot0/brandy；brandy 配置 `sun60iw2p1_a733_defconfig` |
| kernel | `radxa/kernel` @ `allwinner-aiot-linux-6.6` | 全志 6.6 BSP（6.6.98） |
| BSP | `radxa/allwinner-bsp` @ `cubie-aiot-v1.4.8` | `drivers/ve`（cedar-ve 编解码）、`drivers/rt-media`、`configs/linux-6.6/*.dtsi` |
| 设备树 | `radxa/allwinner-device` @ `device-a733-v1.4.8` | `configs/cubie_a7z/linux-6.6/board.dts`、`sys_partition.fex`、`env.cfg` |
| rootfs | 本仓库 `vendor/rootfs/micro` | sysvinit + busybox + ZRAM + 开机扩容 |

内核树 6.6 的顶层 Makefile 自带 `drivers-y += bsp/` 与 `-I$(srctree)/bsp/include`，
所以把 `allwinner-bsp` 挂到内核树根的 `bsp/` 就是官方的拼装方式，`drivers/ve` 会跟着编进去。

## 目录内容

- `microduck.config`：叠在 `defconfig` 上的精简配置，**保留视频编解码**
  （`CONFIG_AW_VIDEO_ENCODER_DECODER` + `AW_VIDEO_KERNEL_DEC/ENC` + `VIDEO_RT_MEDIA`），
  去掉 DRM/FB/GPU、USB、PCIe、以太网、netfilter/IPv6、多余文件系统、调试设施。
- `overlay/`：micro rootfs 的 A733 版本（console `ttyS0,115200`、模块清单）。
- `boot.cmd`：u-boot 启动脚本（`fatload` Image/dtb + `booti`，root 指向 `/dev/mmcblk0p4`）。
- `sys_partition.fex`、`env.cfg`：板厂原始分区表与启动参数，`./bsp pack` 直接读它们。

## 用法

```bash
cp config.env.example config.env
./bsp config PLATFORM=a733
./bsp env          # build-essential / aarch64 交叉链 / dtc / dosfstools / mtools / mkimage
./bsp setup        # 官方 u-boot、kernel 6.6、allwinner-bsp、allwinner-device
./bsp uboot        # 官方 u-boot + boot0（走仓库自带 build.sh）
./bsp kernel       # 挂 bsp/、拼 A7Z dts、defconfig+microduck.config、出 Image+dtb
./bsp rootfs       # micro 精简 rootfs
./bsp pack         # 按 sys_partition.fex 组 MBR 镜像
```

## 镜像布局（来自 `sys_partition.fex`）

| 区域 | 大小 | 内容 |
|---|---|---|
| MBR 保留区 | 16 MB | boot0 写在 8 KiB、u-boot 写在 128 KiB |
| boot-resource | 32 MB | 留空（不放 logo） |
| env | 16 MB | 留空（用 u-boot 默认环境） |
| boot | 96 MB | FAT32：`Image`、`sun60i-a733-cubie-a7z.dtb`、`boot.scr` |
| rootfs | 7.27 GB | `out/rootfs.ext4`（micro，开机 `resize2fs` 自适应） |
| private | 16 MB | 留空 |

镜像用 `truncate` 生成稀疏文件，`A733_IMAGE_NAME` 可改。

## 状态

**已验证**：

- A7Z 的 6.6 设备树（device 的 `board.dts` + BSP 的 `sun60iw2p1*.dtsi`）在 6.6 内核树上
  `cpp + dtc` 编译通过（156365 字节 dtb，含 `ve@`/`codec` 节点）；
- `sys_partition.fex` 解析、打包脚本流程（boot0@8K、u-boot@128K、分区偏移累加）。

**未验证**（本机没有 A733 板子，也没有完整的 Allwinner brandy 工具链）：

- `./bsp uboot` 依赖官方 u-boot 仓库自带的 `build.sh`；若该分支没带 brandy 构建脚本，
  需要按 Allwinner longan 的方式补 `dramlib`/`arisc`/`tools` 后再编；
- boot0/u-boot 的写入偏移（8 KiB / 128 KiB）按 Allwinner 惯例，需上板确认；
- `boot.scr` 里的 `mmc 0:3`/`/dev/mmcblk0p4` 与分区表一致，但实际启动需真机验证。
