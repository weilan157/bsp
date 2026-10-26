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

## 镜像布局（rsdk 官方布局）

依据 `RadxaOS-SDK/rsdk` 的 `src/share/rsdk/build/image.jsonnet` 与
`configs/socs.json`（a733：`partition_table_type=gpt`、`firmware_type=u-boot`），
bootloader 偏移来自 u-boot 包里的 `setup.sh update_bootloader`（等价于
`radxa-pkg/u-boot-aw2501` 的 `setup/u-boot_setup-allwinner-a733.sh`）：

| 区域 | 大小 | 内容 |
|---|---|---|
| 0..16 MiB | 16 MiB | **boot0 @128 KiB**、boot0_ufs @2064 扇区、**`boot_package.fex` @12 MiB** |
| p1 `config` | 16 MiB | FAT16，空分区（rsdk 的 `/config`，fstab 用 `UUID=` 挂载） |
| p2 `rootfs` | 32 MiB..末尾 | ext4；`/boot/Image`、`/boot/<dtb>`、`/boot/boot.scr`、`/boot/extlinux/extlinux.conf` |

`sys_partition.fex`（boot-resource/env/boot/rootfs/private 的板厂 MBR 布局）保留作参考，
`./bsp pack` 已不再使用。

`root=` 用 rootfs 的 `UUID=`（rsdk 的 image.jsonnet 也是把 extlinux.conf / cmdline 里的
root 换成 `UUID=<rootfs>`）。这颗 u-boot 没有 `sysboot`/extlinux 支持，实际启动靠
`distro_bootcmd` 扫描到 `/boot.scr` 后 `source`。

## boot0 与 boot_package.fex（官方工具）

`device/bin` 里的 `boot0_sdcard_sun60iw2p1.bin` **只是模板**，直接用会死在 BROM →
boot0 阶段（错误 DDR 时序，串口一个字都没有）。官方打包时必须做两步：

1. `sys_config.fex` → `sys_config.bin`（`tools/pack/pctools/linux/mod_update/script`）；
2. `update_boot0 boot0_sdcard.bin sys_config.bin SDMMC_CARD` 把板级 DRAM/GPIO 注进去
   （官方还会跑 `update_chip` 写 awbs 的芯片信息）；
3. u-boot 不能裸放：用 `dragonsecboot -pack` 按 `[package]` 清单打成 TOC1 包，
   里面必须有 **monitor（BL31/ATF）**，boot0 先跳 BL31 再跳 u-boot。

`./bsp uboot` 现在会自己稀疏克隆 `gitlab.com/tina5.0_aiot/lichee/tools`
（`A733_TOOLS_DIR`，默认 `sources/a733/awtools`）并完成上面三步，
产物是 `out/a733/uboot/{boot0.bin,boot0_ufs.bin,boot_package.fex,sys_config.bin}`。
注入后的 boot0 与模板差 ~200 字节，`boot_package.fex` 里有 `u-boot` + `monitor` 两个 item。

## 状态

**已验证**（2026-10-24，WSL2 Ubuntu 22.04.5）：

- A7Z 的 6.6 设备树（device 的 `board.dts` + BSP 的 `sun60iw2p1*.dtsi` + 我们的
  `microduck-a7z.dtsi`）`cpp + dtc` 编译通过（154 KiB dtb，含 `ve@`/`codec` 节点）；
- `./bsp uboot`：官方 u-boot（AArch32，`ARCH=arm CROSS_COMPILE=arm-linux-gnueabi-`，
  与官方打包仓库一致；告警用官方的 `EXTRA_CFLAGS="-Wno-…"` 关掉）编出
  `u-boot.bin` 1.2 MB + `u-boot.dtb` 40 KB（`model = "Radxa Cubie A7Z"`），
  再用官方 `update_boot0` / `dragonsecboot` 生成注入过 sys_config 的 boot0 和
  带 BL31 的 `boot_package.fex`（1.3 MB）；
- `./bsp pack`：按 rsdk 布局生成 379 MB 的 `a733-micro.img`——GPT、
  boot0@128 KiB / boot0_ufs@2064 扇区 / `boot_package.fex`@12 MiB、
  p1 `config` FAT16 @16 MiB、p2 `rootfs` ext4 @32 MiB，`/boot.scr` 与 extlinux.conf
  都在 rootfs 的 `/boot` 下，fstab 的 UUID 与实际卷 UUID 一致。

**未验证**（本机没有 A733 板子）：

- 真机启动：之前用「未注入 sys_config 的 boot0 + 没有 BL31 的包」是**完全无输出**
  的，现在这两处都按官方做法修正了，但还没上板复测；
- `distro_bootcmd` 扫到 `/boot.scr` 后 `load mmc 0:2` / `booti` 的实机启动。

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
## 配网 / SSH / 手柄

- `overlay/usr/sbin/microduck-net`：多 WiFi profile（wpa_supplicant，无 NetworkManager），
  `auto` 开机自动连；`add/switch/forget/list/scan/status` 现场换网；
- `overlay/usr/sbin/microduck-ip`：打印所有接口地址和 SSID；
- `overlay/usr/sbin/microduck-pad` + `etc/udev/rules.d/90-microduck-pad.rules`：
  joystick 热插拔 → `/run/microduck/pad.json` + 拉起 robotd；
- `etc/microduck/rc.d/20-network.sh`：rcS 末尾启动 udevd → dbus/avahi → sshd → WiFi → 蓝牙 →（可选）AP；`microduck-bt`（bluetoothd 常驻 + Xbox 自动配对/回连）、`microduck-ap`（AP+STA 共存 + busybox httpd 配网页）；
- micro rootfs 里装了 `openssh-server`（root 密码登录，`sshd_config.d/10-microduck.conf`）、
  `dbus`、`avahi-daemon`、`libnss-mdns`（`<host>.local` 可解析）。

产品层的完整“傻瓜式”方案（AP 先起、per-device SSID/PSK、captive portal、换网常驻页面、
蓝牙手柄自动回连、断开急停）见 `docs/ux-network-gamepad.md`。
## 调试串口

`&uart0`（PB9/PB10 = 40-pin 8/10）给了舵机，`boot.cmd` 的 console 是 `tty1`；
A7Z 无显示时相当于没有 console。换口方案（UART2/7-11、USB-C gadget、SSH-only 的取舍）
见 [`docs/uart-console-vs-servo.md`](../../docs/uart-console-vs-servo.md)。
## u-boot 与官方差异 / DDR 初始化

`./bsp uboot` 用的就是官方 `radxa/u-boot` 源码，只改构建配置和两处小修；与 rsdk 的差别
主要在 boot0 是预编译还是现编、boot_package 里有没有 ARISC/NOR 变体。boot0 的 DRAM
初始化（“DDR 速率探测”）在预编译 boot0 里，sys_config 没有 `[dram_para]`，改它要重编
brandy/dramlib，难度高。详见 [`docs/uboot-vs-official.md`](../../docs/uboot-vs-official.md)。
生产默认 `debug_mode=0`（`A733_BOOT0_DEBUG=y` 可恢复 boot0 日志）。