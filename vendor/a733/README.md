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
./bsp hal          # 检查 dtb 是否满足 HAT 的 BSP/HAL 基本要求
./bsp pack         # 按 sys_partition.fex 组 MBR 镜像
```

## 设备树（HAT 适配）

`dts/microduck-a7z.dtsi` 叠在官方 `board.dts` 之后（`./bsp kernel` 生成
`sun60i-a733-cubie-a7z.dts` = `#include "board-a7z.dts"` + `#include "microduck-a7z.dtsi"`），
对应主控移植清单：

| HAT 信号 | RK3566 | A733（本 dts） |
|---|---|---|
| 舵机串口 | `/dev/ttyS2` | `&uart0` = **PB9/PB10**（pin 8/10）；官方 `uart0_pins_active` 的 pins 是空的，这里换成真实引脚 |
| console | ttyS2 | 移到 `tty1`（`vendor/a733/boot.cmd`），UART0 只给舵机 |
| I2C（codec/IMU/Stemma） | `/dev/i2c-3` | `&twi7` = **PJ22/PJ23**（pin 3/5），400 kHz → `/dev/i2c-7`；设备：`tlv320aic3104@0x18`、`vl53l5cx@0x29`、`bmi088-accel@0x19` / `bmi088-gyro@0x68`（D1 版的 `lsm6dsv16x@0x6a` 注释着） |
| 音频 codec | i2s3_2ch | `&i2s0_plat`/`&i2s0_mach` = **PB4/5/6/7/8**（pin 36/12/35/40/38），soundcard-mach 挂 `tlv320aic3104@0x18` |
| 关机检测 | GPIO6 | `gpio-keys` on **PB2**（pin 31，原理图确认 pin 31=PB2）→ `KEY_POWER` |
| BMI088 中断 | GPIO22 | PL7，软件不用（未配） |
| HAT ID I2C | GPIO0/1 | 排针 27/28 = TWI2-SDA/SCK，EEPROM DNP（未配） |
| 显示 | HDMI | 关掉 `&de`/`&hdmi0`/`&hdmi_codec`，HDMI 音频 `&i2s3_*` 也关 |
| 摄像头 IMX219 | rpi-camera-v2 | `dts/microduck-a7z-camera.dtsi`（`A733_WITH_CAMERA=y`）：J5 是 4 通道 MIPI CSI，走 VIN `sensor0`（`imx219`、TWI3、0x20、MCLK0）；复位/待机 GPIO 和 TWI3 引脚 mux 需按原理图 GPIO 页补 |

**已实测**：这套 dts（官方 board.dts + 本 dtsi）在 6.6 内核树上 `cpp + dtc` 编译通过，
157272 字节 dtb，`twi7`/`tlv320aic3104`/`i2s0_plat`/`i2s0_mach`/`hat-power-detect`/`PB3`
都在。用户态节点名（`/dev/ttyAS0` 还是 `/dev/ttyS0`、`i2c-7`）以驱动实际枚举为准。

## 镜像布局（来自 `sys_partition.fex`）

| 区域 | 大小 | 内容 |
|---|---|---|
| MBR 保留区 | 16 MB | **boot0 @128 KiB**、**`boot_package.fex` @12 MiB**（u-boot 的 TOC1 包） |
| boot-resource | 32 MB | 留空（不放 logo） |
| env | 16 MB | 留空（用 u-boot 默认环境） |
| boot | 96 MB | FAT32：`Image`、`sun60i-a733-cubie-a7z.dtb`、`boot.scr` |
| rootfs | 7.27 GB | `out/rootfs.ext4`（micro，开机 `resize2fs` 自适应） |
| private | 16 MB | 留空（MBR 只有 4 个主分区槽位，这个分区只在镜像尾部占位） |

镜像用 `truncate` 生成稀疏文件，`A733_IMAGE_NAME` 可改。

## 状态

**已验证**（2026-10-23，WSL2 Ubuntu 22.04.5）：

- A7Z 的 6.6 设备树（device 的 `board.dts` + BSP 的 `sun60iw2p1*.dtsi`）在 6.6 内核树上
  `cpp + dtc` 编译通过（154 KiB dtb，含 `ve@`/`codec` 节点）；
- `./bsp uboot`：官方 u-boot（AArch32，`ARCH=arm CROSS_COMPILE=arm-linux-gnueabi-`）
  编出 `u-boot.bin` 1.2 MB + `u-boot.dtb` 40 KB（`model = "Radxa Cubie A7Z"`），
  再用 `vendor/a733/mk_boot_package.py` 打成 TOC1 的 `boot_package.fex`（1.5 MB，
  结构与 Radxa 官方包逐字节对齐，除 `add_sum`）；
- `./bsp pack`：生成 7.5 GB 稀疏 `a733-micro.img`，boot0@128 KiB、`boot_package.fex`@12 MiB、
  MBR 四分区（boot-resource/env/boot/rootfs）、FAT32 boot 分区与 ext4 rootfs 都能正常挂载读取。

**未验证**（本机没有 A733 板子）：

- boot0 → `boot_package.fex` 的实际加载（12 MiB 这个偏移来自板厂镜像 / OpenWrt 的
  `radxa-cubie-a7z` setup 脚本，不是官方文档）；
- `boot.scr` 里 `fatload mmc 0:3` / `root=/dev/mmcblk0p4` 的实机启动。

## u-boot 设备树

u-boot 的板级 dts 在 **u-boot 源码里**，不是单独一份文件：

```
arch/arm/dts/sun60i-a733-cubie-a7z.dts      # 板级（model/compatible/外设）
   └─ #include "../../../../device-a733/configs/cubie_a7z/uboot-board.dts"   # allwinner-device
```

那个 `../../../../` 是相对 **u-boot 源码的父目录**，所以 `./bsp uboot` 会先做两件事：

1. `ln -sfn sources/a733/device sources/a733/device-a733` —— 让 include 能落到 device 仓库；
2. 修 Allwinner 源码里的宏名拼写错误 `_SUNXI_PMIS_BUS_H` → `_SUNXI_PMIC_BUS_H`（新版 GCC 下会重定义）。

**已实测**：按这个布局对 `sun60i-a733-cubie-a7z.dts` 做 `cpp + dtc`，通过，40669 字节 dtb，
`uboot-board.dts` 的内容确实被 include 进来了。

参考 [hqu-little-boy/archlinuxarm-a733](https://github.com/hqu-little-boy/archlinuxarm-a733)：
它本身**不带** u-boot dts，也是用 `radxa/u-boot` + `allwinner-device` 这套源码；
它的做法是把 `device-a733` 拷进 u-boot 树里再 `sed` 改 include 路径（我们用符号链接代替），
## 启动裁剪（参考 Tina《系统裁剪开发指南》v1.8）

文档是全志 2025.04 的《Tina Linux 系统裁剪开发指南》，主线是省 flash；1.1 也说明
裁剪后"通常也会提升启动速度"，所以按它的条目挑了能落地的：

| 文档条目 | 本项目做法 |
|---|---|
| 2.3.1 删除不使用的功能 | `microduck.config` 关掉 `KALLSYMS`、`ELF_CORE`、`PROC_KCORE`、`AIO`、`POSIX_MQUEUE`、`SYSV_IPC`；`SWAP`/`SHMEM` 保留（ZRAM 和日常程序要用） |
| 2.3.2 删除不使用的驱动 | DRM/FB/GPU、USB、PCIe、以太网、多余文件系统都已关（见上文） |
| 2.4.3 应用与库 strip | `ROOTFS_STRIP=y`，用 `aarch64-linux-gnu-strip --strip-unneeded` 处理可执行文件和 `.so`（跳过 `ld-*.so`）。实测只省 ~5 MB：Debian 的包本身已经 strip 过，这条对 buildroot 类 rootfs 才明显 |
| 2.4.1 删冗余文件 | micro rootfs 已去文档/locale/apt lists；没有 strace/tcpdump 这类调试工具 |
| 2.4.2 换小 C 库 | 仍用 glibc（musl 要整盘重编，收益大但工作量大），暂不做 |

内核压缩（文档 2.3.3.4 的实测表，加载+解压总时间）：

| 压缩 | 镜像 | 加载 | 解压 | 总时间 |
|---|---|---|---|---|
| GZIP | 2.31M | 124ms | 89ms | 213ms |
| LZO | 2.53M | 136ms | 23ms | **159ms** |
| LZ4 | 2.68M | 143ms | 27ms | **170ms** |
| XZ | 1.95M | 104ms | 667ms | 771ms |

结论：**要快就 LZO/LZ4，别用 XZ**。arm64 内核本身不支持自解压，压缩是在打包时由
bootloader 做的；我们现在的 `pack` 是 `fatload Image` + `booti`（不压缩），以后如果让
u-boot 解压（`Image.lz4` + u-boot lz4 支持），选 LZ4/LZO。

文件系统压缩（2.4.4）：squashfs 更省空间但只读；micro 需要可写 + ZRAM，继续用 ext4。

不适用：**2.1 boot0 裁剪、2.2 uboot 裁剪/压缩** —— 都在 longan 的 boot package 里做，
我们的 `pack` 不生成 boot0/u-boot，这两块仍用官方产物。
## 内核构建的坑（6.6 BSP）

Allwinner 的 6.6 BSP 是按 longan 的构建环境写的，脱离 longan 直接 `make` 会踩这些：

| 现象 | 原因 | `./bsp kernel` 的处理 |
|---|---|---|
| `bsp/Kconfig: can't open file "platform/Kconfig"` | Kconfig 用 `$(BSP_TOP)` 拼路径 | `export BSP_TOP=<kernel>/bsp/`（结尾斜杠） |
| `KERNEL_SRC_DIR not setup` | `modules/nand/Makefile` 要 `LICHEE_KERN_DIR` | `export LICHEE_KERN_DIR=<kernel>` |
| `/work/bsp/drivers/ve/... 不是目录` | cedar-ve 的 codec Makefile 用 `$(PWD)` 拼绝对路径 | 先 `cd <kernel>` 再 make |
| `sunxi-autogen.h: No such file` | 由 longan 的 `mkkernel.sh` 生成，内容只有 `AW_BSP_VERSION` | 生成到 `bsp/include/` 和 `drivers/clk/sunxi-ng/` |
| `ve_plat_common.c: cedar_ve.h: No such file` | 没选 SoC，`drivers/ve` 走了 common 分支 | 打开 `AW_BSP/ARCH_SUN60I/ARCH_SUN60IW2/ARCH_SUN60IW2P1` |
| `multiple definition of ccu_*` | 主线和 BSP 各有一套 sunxi-ng | 关掉主线的 `CONFIG_SUNXI_CCU` |
| rt-media 报 `field 'tv' 不完整`、`../vin/vin-video/vin_video.h` 缺失 | 6.6 BSP 里 rt-media 还引用旧 VIN 布局 | 关掉 `CONFIG_VIDEO_RT_MEDIA`（编解码用 cedar-ve） |
| `dt-bindings/clock/sun60iw2-ccu.h: No such file` | BSP 的 dt-bindings 不在内核 include 里 | 编 dts 时把 `bsp/include` 加进 `DTC_INCLUDE` |

`Image` 编出来后（37 MB），dtb 用 **cpp + dtc 单独编**（几十毫秒），不再 `make dtbs`
（那会把 mainline 的 dts 全编一遍，1-2 分钟）；增量构建整体约 11 秒。

可选 `A733_KERNEL_COMPRESS=lz4`：额外生成 `Image.lz4`（37.7 MB → 14.7 MB，39%，
`lz4 -l` legacy 格式）。**注意**：radxa/u-boot 2018.07 的 `cmd/` 里没有 `lz4` 命令，
也没有 lz4 的解压路径，所以这个产物目前只是留档/实验；要真用必须改 u-boot（加 lz4 命令或
在 bootm 里解压），和“完全用官方 u-boot”的前提冲突。默认启动仍走未压缩 `Image`。