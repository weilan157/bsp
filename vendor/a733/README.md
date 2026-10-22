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
| 关机检测 | GPIO6 | `gpio-keys` on **PB3**（pin 31）→ `KEY_POWER` |
| BMI088 中断 | GPIO22 | PL7，软件不用（未配） |
| HAT ID I2C | GPIO0/1 | PD16/PD17，EEPROM DNP（未配） |
| 显示 | HDMI | 关掉 `&de`/`&hdmi0`/`&hdmi_codec`，HDMI 音频 `&i2s3_*` 也关 |
| 摄像头 IMX219 | rpi-camera-v2 | `dts/microduck-a7z-camera.dtsi`（`A733_WITH_CAMERA=y`）：J5 是 4 通道 MIPI CSI，走 VIN `sensor0`（`imx219`、TWI3、0x20、MCLK0）；复位/待机 GPIO 和 TWI3 引脚 mux 需按原理图 GPIO 页补 |

**已实测**：这套 dts（官方 board.dts + 本 dtsi）在 6.6 内核树上 `cpp + dtc` 编译通过，
157272 字节 dtb，`twi7`/`tlv320aic3104`/`i2s0_plat`/`i2s0_mach`/`hat-power-detect`/`PB3`
都在。用户态节点名（`/dev/ttyAS0` 还是 `/dev/ttyS0`、`i2c-7`）以驱动实际枚举为准。

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
