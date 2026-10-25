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
- `overlay/`：micro rootfs 的 A733 版本（`etc/inittab` 给 `ttyAS0` 挂 getty、模块清单）。
- `patches/kernel/`：打在 `allwinner-bsp` 驱动上的补丁，`./bsp kernel` 会自动应用（幂等）。
  目前只有一个 `0001-sunxi-mmc-a733-ccu-workaround.patch`（见下文「上板必须的修法」）。
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

**已在真机跑通**（2026-10-24，Cubie A7Z / A733，SD 卡启动）：

```
mmc0: new high speed SDHC card at address 5048
mmcblk0: mmc0:5048 SD32G 29.7 GiB
mmcblk0: p1 p2
EXT4-fs (mmcblk0p2): mounted filesystem ... r/w with ordered data mode
Run /sbin/init as init process
microduck: userspace ready in 2.74s
INIT: Entering runlevel: 2
Debian GNU/Linux 13 (none) ttyAS0
(none) login:
```

上电到 login 约 **2.7 s**（内核 1.7 s + 用户态 1 s），串口是 UART0 = `ttyAS0`，115200。

**WiFi 已在真机跑通**（2026-10-25）：

```
aicwf_usb_probe vid:0xA69C pid:0x8D80 → matched chip: aic8800d80
rwnx_interface_add: wlan%d, 2, 10
ieee80211 phy0: New interface create wlan0
2: wlan0: <BROADCAST,MULTICAST> mtu 1500 ... link/ether c3:82:00:80:ff:ff
```

## 上板必须的修法（从「完全无输出」到能登录）

| 现象 | 根因 | 修法 |
|---|---|---|
| 完全无输出 | boot0 的 DRAM 参数不对 / u-boot 没带 BL31 | 用官方 `vendor/a733/boot0_sdcard.bin` + 官方 `boot_package.fex`（不再自己 pack） |
| `GUID Partition Table Entry Array CRC is wrong` | u-boot Kconfig 里 GPT 表项默认 56 条，sfdisk 写了 128 条 | 打包后把 GPT 改成 56 项（`gpt56.py`），p2 打 `LegacyBIOSBootable` |
| `unknown pin PG*/PC*/PF*`、pinctrl 永远 `-517` | `CONFIG_AW_FPGA_S4=y` 让 pinctrl 编了 FPGA 的 104-pin 表 | 关掉 `AW_FPGA_S4/V7`，开 `CONFIG_AW_IC_BOARD=y`（完整 181 pin / 10 bank） |
| 所有 SPI 中断 `-517 / -22` | 根 `interrupt-parent` 是 `sunxi-wakeupgen`，但驱动没编 | `CONFIG_AW_WAKEUPGEN=y` |
| `uart-ng: cannot get the TX DMA channel` | 没编 DMA | `CONFIG_AW_DMA=y` |
| `sunxi_get_soc_ver()` 走 weak 桩 | 没编 SID | `CONFIG_AW_SID=y` |
| sdc0 probe 卡死（无任何输出） | `resource_request()` 末尾关总线时钟后紧跟寄存器访问 | 保持总线时钟常开（补丁第 2 段） |
| `sdc set ios:clk 400000Hz` 后整机冻住 | `sunxi_mmc_clk_set_rate_for_sdmmc_v5p3x()` 里 `clk_set_parent()/clk_set_rate()` 在 CCU 上死锁 | 跳过 CCU，直接写 `CLKCR[7:0]` 分频（补丁第 1 段） |
| 命令发出但收不到中断 | 上面时钟/中断修好后自然恢复 | — |
| `EXT4-fs: bad geometry: block count ... exceeds size of device` | 打包时 p2 比文件系统小（少给 GPT 备份留扇区） | `img_size` 按实际 `rootfs.ext4` 大小算，再 +8 MiB |
| `INIT: id field too long (max 4 characters)`，没有 login | busybox init 的 id 必须 1~4 字符，`ttyAS0` 是 6 个 | inittab 用 `tS0`，rcS 里建 `/dev/tS0 -> /dev/ttyAS0` |

**关于「官方为什么不用打补丁」**：官方 A733 的 `bsp/configs/linux-6.1/sun60iw2p1_min_defconfig`
用的是 `CONFIG_AW_FPGA_V7=y`（FPGA 分支，pin 表精简、且不真正编程 PLL），时钟由 boot0/u-boot
配好即可；我们为了修 pinmux 改成了 `AW_IC_BOARD`，内核才开始真去改 SMHC0 时钟，于是踩到 CCU
死锁。后续优化方向就是把这套配置尽量往官方靠（见下）。

## WiFi（aic8800 / FCU760K，USB 单接口）

这颗模块的驱动链路非常「多层门禁」，每一层都是**代码里有、但没走到**。完整踩坑记录：

| 层 | 现象 | 根因 | 修法 |
|---|---|---|---|
| 1 | `/sys/bus/usb/devices` 完全为空 | `bsp/drivers/usb/Makefile` 只有 `CONFIG_USB_SUNXI_HCI` 才进 `host/` 子目录，而它又依赖 `USB_SUNXI_HCD` | 补 `CONFIG_USB_SUNXI_HCD=y` + `USB_SUNXI_HCI=y` |
| 2 | 编译报 `sunxi_usb_debug.h: No such file` | `sunxi-hci.h` 用 `<../sunxi_usb/include/...>`（尖括号只查 -I 路径），host/ 没把自己加进搜索路径 | `patches/kernel/0005`：host/Makefile 加 `ccflags-y += -I $(srctree)/$(src)` |
| 3 | 驱动编进去了但 `probe` 从不触发 | `ehci-sunxi.c` 的 `SUNXI_EHCI0_OF_MATCH` 在 `CONFIG_USB_SUNXI_EHCI0` 未开时被编译成 `"null"` | 开 `USB_SUNXI_EHCI0/OHCI0/EHCI1/OHCI1` |
| 4 | host 起来了但设备不枚举 | `ehci/ohci-sunxi` 依赖 BSP 的 USB PHY | 开 `CONFIG_USB_SUNXI_PHY` + `USB_SUNXI_AWPHY` |
| 5 | `request_firmware` 全失败 | BSP 根本不含 aic8800 固件 | `vendor/a733/firmware/`（aic8800dc + aic8800d80，含 u03 别名），pack 时铺到 `/lib/firmware` |
| 6 | `fw_patch_table_u03.bin` / `(null)0.bin` 失败 | 驱动按 rev 选固件表；u01 表没有 `.bt_ext_patch` 字段，但 patch table 里带 ext 项 | `aicbt_ext_patch_data_load()` 加 NULL 保护跳过 |
| 7 | 设备枚举但 `UNBOUND`，`probe` 日志都没有 | 本工程 `CONFIG_USB_BT` 打开，实际编译的是 `#else` 分支；`8d80` 只加在 `#ifndef` 分支里等于没加 | `aicwf_usb.c` 的 `#else` 分支补 `8D80/8D81`（按 `ff/ff/ff` 接口匹配） |
| 8 | `Number of interfaces: 1 not supported` | `CONFIG_USB_BT` 分支硬性要求 3 个接口，实物只有 1 个 | `aicwf_parse_usb()` 放宽为 1 或 3 |
| 9 | `rwnx_cfg80211_init` 空指针 Oops | `feature.chipinfo` 来自 bsp；bsp 不认 `8d80` 时它是 NULL | bsp 识别 `8d80` 并填 `aicbsp_info.chipinfo`，但 `return -ENODEV` 不绑定，把设备留给 fdrv |

模块加载顺序（`/etc/microduck-modules`，由 rcS 里的 `microduck-wifi` 后台 modprobe）：
`aic8800_bsp` → `aic8800_fdrv`（fdrv 有符号依赖，会自动带起 bsp）。

注意：`0x8d80` 这颗模块**始终不重新枚举**（固件下载前后 PID 不变），所以厂商那套
「bootloader PID → 重枚举成 app PID」的流程在这里不成立，必须靠上面的归属划分解决。

## 已知限制 / 待办

- **蓝牙未通**：`aic_btusb` 需要 class `e0` 的 USB 接口，而 FCU760K 只有 1 个 `ff/ff/ff`
  接口（WiFi/BT 共用），且这个设备被 `aic8800_fdrv` 独占。后续要验证 BT 到底走
  USB 复用、UART（BSP 里有 `aic8800_btlpm`）还是其它通路，再决定接法。
- **摄像头未通**：IMX219 的 DT（`sensor_list0`/`sensor0`/`vinc00`/`twi3`）已配好、
  VIN 已移植进内核，但 `5800800.vind` 一直 `deferred probe timeout (-110)`，
  `vin_probe` 内部某个依赖拿不到，尚未定位到具体项。
- `i2c 13-0036`（AXP8191 PMIC）仍 `deferred probe pending`；`cpufreq-dt` 同样 pending。
  PMIC 的 `MFD_AXP2101/AXP8191` 注册路径还没打通（`AW_MFD_AXP2101` 已开但其 i2c 驱动未绑）。
- cedar-ve（视频编解码）probe 报 `-110`，依赖没就绪，不影响启动。
- `regulatory.db` 缺失（`cfg80211: failed to load regulatory.db`），WiFi 频道表用默认值，
  需要时把 `wireless-regdb` 的 db 放进 `/lib/firmware`。
- WiFi 的 MAC 读出来是 `c3:82:00:80:ff:ff`（efuse MAC 读取路径可能没成功），
  需要时可在 DT/驱动里补 MAC 来源。
- sdc1/sdc2 在 DT 里 disabled（本板只有 SD 槽，无 eMMC）。
- u-boot 启动仍有 `Boot menu / Enter choice` 交互过程，`extlinux.conf` 里加
  `timeout 0` + `default` 可以免按键直启（待验证）。


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