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

**蓝牙手柄（Xbox）已验证可用**（2026-10-27）：

```
Pairing successful → Paired: yes / Bonded: yes / Trusted: yes / Connected: yes
microduck-pad: 手柄连接: js0
input: Xbox Wireless Controller as /devices/virtual/misc/uhid/0005:045E:02FD.0001/input/input1
/dev/input/js0  /dev/input/event1
```

三个必备条件（少一个都连不上）：
1. `/etc/bluetooth/input.conf`：`UserspaceHID=true`、`ClassicBondedOnly=false`；
2. **配对成功后必须持续 connect**：Xbox 手柄配对完会主动断一次（`reason 3`），
   BlueZ 会把它标成 `Paired: no`，必须重连才能建起 HID 通道
   （`microduck-bt-pair` 里是 10 次 / 2s 的重试环）；
3. 内核：`CONFIG_UHID=y`（BlueZ 通过 uhid 创建输入设备）+ `CONFIG_INPUT_JOYDEV=y`。

**WiFi STA + AP 共存已验证**（2026-10-27）：

```
wlan0  192.168.0.154  (STA, ZTE_B82B8E, ch36/80MHz)
ap0    10.42.0.1      (AP, duck-061f, ch6)       ← 同时在线
```

注意：`net.ifnames=0` 必须加到内核 cmdline，否则 systemd/udev 会把 wlan0
改名成 `wlx<mac>`（USB 网卡的可预测命名），脚本等不到 wlan0。

**IMX219 1080p 抓帧成功**（2026-10-25）：

```
microduck-cam                 → /tmp/frame.raw = 4,177,920 字节，0.22s
microduck-cam 640 480 10 ...  → /tmp/f.raw    = 6,144,000 字节（=640*480*2*10）
```

**rootfs 自动扩容到整卡**（2026-10-25）：

```
microduck: grow target /dev/mmcblk0p2
microduck: partition /dev/mmcblk0p2 extended with sfdisk
EXT4-fs (mmcblk0p2): resized filesystem to 7786494
/dev/root  28G  237M  27G  1% /
```

**蓝牙手柄已在真机跑通**（2026-10-25，Xbox Wireless Controller）：

```
input: Xbox Wireless Controller as /devices/virtual/misc/uhid/0005:045E:02FD.0001/input/input1
microsoft 0005:045E:02FD.0001: input: BLUETOOTH HID v9.03 Gamepad
/dev/input/js0  /dev/input/event1
```

**IMX219 摄像头已在真机跑通**（2026-10-25）：

```
sunxi-twi 2513000.twi: probe success            ← TWI3(PE3/PE4)
sunxi:vin:[INFO]: [imx219]find the sony IMX219  ***********
/dev/media0  /dev/video0
i2c-3: SUNXI TWI(0x0000000002513000)
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

## WiFi（AIC8800D80 / FCU760K，USB）

**已在真机跑通**（2026-10-25）：设备从 `a69c:8d80` 重新枚举为 `a69c:8d81`，
`aic8800_fdrv` 建出 `wlan0`（真实 MAC）、射频校准完成、`ip link set wlan0 up` 返回 0。

### 最终采用的方案：Radxa 官方 USB 驱动包

最终不是用 BSP 自带的那套 `aic8800_bsp`，而是 **Radxa 官方 USB 驱动包**
（`radxa-pkg/aic8800`，与本模组原厂配对），因为它把两件事拆成两个模块：

| 模块 | 职责 | 绑定阶段 |
|---|---|---|
| `aic_load_fw` | 只负责下载并启动固件 | `a69c:8d80`（Boot ROM） |
| `aic8800_fdrv` | 只负责建 `wlan0` | `a69c:8d81`（运行态） |

- 源码放在 `vendor/a733/aic8800-usb/`，**以外部模块方式构建**（不改 BSP 仓库）；
- `scripts/mod-a733.sh` 的 `a733_build_aic8800_usb()` 在 pack 时编译并安装到
  `/lib/modules/<rel>/extra/`；`aic8800_fdrv` 需要
  `KBUILD_EXTRA_SYMBOLS=<load_fw>/Module.symvers`（两模块间有符号依赖）；
- `microduck.config` 关掉 `AIC_WLAN_SUPPORT` / `AIC8800_WLAN_SUPPORT` /
  `AIC8800_BTUSB_SUPPORT`（BSP 的模块名与 Radxa 的 `aic8800_fdrv` 冲突且跑不通）；
- `/etc/microduck-modules` 加载 `aic_load_fw` → `aic8800_fdrv`。

### 固件目录大小写

- Radxa 驱动按**大写**找固件：`/lib/firmware/aic8800D80/...`；
- 仓库在 Windows 文件系统上大小写不敏感，所以仓库统一用**大写**，
  pack 时 `a733_fw_alias_lowercase()` 在 ext4 镜像里再生成小写别名，
  两代驱动都能用（镜像里 `aic8800D80` 与 `aic8800d80` 各有 18 个文件）。

### 走过的弯路（BSP 自带 aic8800_bsp，最终放弃）

BSP 那套把「加载器 + 驱动」揉在一个模块里，实测固件能下载但**启动约 2.5 秒后
自己抛异常**（换哪条命令都在同一时刻 `cmd timed-out` + `rwnx_exception_event`），
期间修过：USB 主机驱动门禁（`USB_SUNXI_HCI`）、`OF_MATCH` 的条件编译、
USB PHY、驱动 ID 表（`8d80` 加在 `#else` 分支）、PID 归属（bsp 与 fdrv 抢设备）、
单接口校验、`chipinfo` 空指针、`CSI_CCI`、`fw_u03` 不存在的固件表、
`MM_SET_STACK_START` 重复启动 —— 都没能救回来，因为根因是驱动与模组不配对。

### 上电后的正常日志

```
aic_load_firmware :firmware path = /lib/firmware/aic8800D80/fw_patch_table_8800d80_u02.bin
... fw_adid / fw_patch / fw_patch_table_8800d80_u02_ext0 / fmacfw_8800d80_u02 ...
（设备重新枚举为 a69c:8d81）
rwnx_send_rf_calib_req in,chipid=5
rwnx_get_countrycode_channels support channel: 1 2 3 ... 165
rwnx_interface_add: wlan%d, 2, 10
New interface create wlan0
wlan0: link/ether 90:30:d6:03:3f:f6
```

## 扩盘（grow）踩坑

首次启动把 rootfs 扩到整张卡，中间踩了 4 层坑，最终方案在
`/usr/sbin/microduck-grow`：

1. `/proc/mounts` 里 root 是 `/dev/root`（不是块设备）—— 旧脚本 `[ -b ]` 直接
   静默退出，所以扩容从来没执行过。改为 `/proc/cmdline` 的 `root=` 兜底；
2. 镜像的 **GPT 备份头写在 p2 末尾**，`parted` 因此提示 "fix the GPT"；
3. 即使修好 GPT，`parted resizepart` 仍报
   `Unable to satisfy all constraints on the partition`（对齐/备份头约束），
   而 `resize2fs` 只能把 ext4 扩到当前分区大小 → 看起来"扩了但没变大"；
4. 最终改用 **`sfdisk`**（growpart 的标准做法，对挂载中分区走 BLKPG）：

```sh
printf ',+,\n' | sfdisk --force --no-reread -N 2 /dev/mmcblk0
resize2fs /dev/mmcblk0p2
```

实测：`98304 -> 7786494 blocks`，`df /` 从 445M 变成 **28G**。

## 音频（TLV320AIC3104）

### 引脚定义（三方对齐，不要再猜）

依据：HAT 原理图 Audio 页放大图 + Cubie A7Z 40-pin 引脚表 +
参考实现（github.com/weilan157/microduck、fanhao375/microduck-replica）。

| 信号 | 40pin | BCM | A733 | I2S0 功能 | 方向 |
|---|---|---|---|---|---|
| SCL | 5 | GPIO3 | PJ22 | twi7 | SoC 出 |
| SDA | 3 | GPIO2 | PJ23 | twi7 | 双向 |
| PCM_CLK / BCLK | 12 | GPIO18 | PB5 | `i2s0_bclk` | SoC 出 |
| PCM_FS / WCLK | 35 | GPIO19 | PB6 | `i2s0_lrck` | SoC 出 |
| PCM_DIN（codec DOUT → SoC） | 38 | GPIO20 | PB8 | `i2s0_din0` | SoC 入 |
| PCM_DOUT（SoC → codec DIN） | 40 | GPIO21 | PB7 | `i2s0_dout0` | SoC 出 |
| PA MODE | 16 | GPIO23 | PJ24 | gpio | — |
| PA MUTE | 18 | GPIO24 | PJ25 | gpio | 低=未静音 |

注意 RPi 的命名视角：`PCM_DIN` 是"进 SoC"的数据，也就是 codec 的 DOUT；
`PCM_DOUT` 是"SoC 出"的数据，也就是 codec 的 DIN。所以
`docs/硬件入门.md` 的 "GPIO18/19/20/21 = Clk/FS/Din/Dout" 与原理图放大图
`IO_21 → DIN`、`IO_20 → DOUT` 并不矛盾，是同一个接线。

**踩过的坑**：曾按"codec DIN 接 PB7 的 dout0"理解反了，把 PB8 改成
`i2s0_dout1`、PB7 改成 `i2s0_din1`，真机更差（codec 掉线、TWI 报错）。
现固定为 board dts 的默认引脚组：PB7=`i2s0_dout0`、PB8=`i2s0_din0`。

### 现状与结论（2026-10-28，真机排查记录）

音频**软件侧已全部对齐但仍无输出**，证据链如下（都是真机日志）：

| 观察 | 结论 |
|---|---|
| `i2cdetect -y 0`（i2c-gpio 版本）只看到 `0x18` 与 `0x6a` | 总线能工作；`0x6a` = D1 版 HAT 的 **LSM6DSV16X** |
| 多数时候解绑驱动后 `i2cget 0-0018 0x02` 全部 `Error: Read failed` | codec **不应答** |
| `i2c i2c-0: Not I2C compliant: can't read SCL` / `Bus may be unreliable` | i2c-gpio 模式下 SCL 回读为低（改用硬件 TWI7 后不再出现）|
| 打过 9 clocks + STOP 后偶发恢复（一次 5/5 可读，寄存器全 0x00） | 状态**间歇性**，典型接触/器件异常 |
| 播放时（经 hw TWI7 或 i2c-gpio）一律 `NAK bailout`，静音播放同样 | 与功放电流无关，是 codec 掉线 |

结论：**codec 侧 I2C 电气异常（SCL 被拉低 / 芯片不应答），属于板级硬件问题，
在不改动硬件的条件下软件无法绕过**。已排除的软件因素：
TWI 速率（400k→100k）、I2C 驱动实现（硬件 TWI 与 i2c-gpio 都试过）、
引脚定义（PB5/6/7/8 与 PJ22/23 均按原理图与 40pin 表核对）、
mixer（含 LOP 静音位）、mclk-fs（250/256）、PLL 旁路、
`simple-audio-card` 与 `soundcard-mach` 两种建卡方式、PA MUTE 极性。

补充（原理图核对）：HAT 的 I2C 上拉是 **R12/R13 = 10k 且已贴装**
（接到 J5 Stemma 座），主板 SoC 侧另有 `bias-pull-up`，因此**上拉不是瓶颈**；
TWI7 降到 50 kHz 只是为了给排线/连接器容性留上升沿余量，不是补上拉。

保留的排查工具（纯软件）：
- `microduck-audio-probe`：hw_params / mixer / 寄存器 / 时钟 / NAK 计数；
- `microduck-i2c-recover`：解绑 i2c-gpio 后打 9 clocks + STOP 尝试救回总线；
- `i2c-recover`：静态小程序，直接用 GPIO（SCL=310/SDA=311）打时序。

若后续换一块 HAT 或修复该总线，只需把 `microduck-audio.service` 打开即可验证：
`systemctl status microduck-audio` / `speaker-test -D hw:0,0`。

### 时钟

- codec MCLK：板上 **Y1 12.000 MHz** 有源晶振直接进 U2（不是 SoC 的 PB4）；
- SoC I2S sysclk：参考实现用 **12.288 MHz**（256×48k）；
- 但 Allwinner 的 `soundcard-mach` 只支持**一个** mclk 值同时给 cpu 和 codec，
  所以这里取 `mclk-fs = <250>`（48000×250 = 12.000 MHz），保证 codec 的
  sysclk 与真实晶振一致（codec PLL 由它换算）；SoC 的 PB4 未接到 codec，
  其数值不影响出声。

### 功放（PAM8406）

- 喇叭接 **J1 螺钉端子**；codec 的 HPOUT/HPROUT 在原理图上未接，插耳机孔不会响；
- 声音走 codec 线输出 LEFT_LOP/RIGHT_LOP（mixer 的 `Line Playback Switch`
  是 LOP 输出级静音位，必须 on）；
- **MUTE（pin18 = PJ25）不需要软件驱动**。PAM8406 的 MUTE 是"低有效 +
  内部上拉"：悬空 = 高 = **不静音**，拉低才会静音
  （Solid 文档 / DIODES 数据手册）。曾错误地加过 `regulator-pa-mute`
  并把 GPIO 配置成 ACTIVE_LOW + always-on，实际会把 MUTE **拉低=静音**，
  方向是反的，已删除。
- **MODE（pin16 = PJ24）**：芯片不允许悬空；HAT 上它接我们的 UART4 TX，
  串口空闲为高 → **Class-D**，正好是默认工作模式，无需额外处理。
- 结论：功放侧软件不需要任何动作；喇叭必须接 **J1 螺钉端子**。

HAT 上的 codec 挂在 **TWI7 @0x18**，走 **I2S0**（PB4–PB8 = MCLK/BCLK/LRCK/DOUT/DIN）。

- DT：`audio_codec: tlv320aic3104@18` + `&i2s0_mach`（name `microduck-audio`，
  `mclk-fs=256`，frame/bitclock master = SoC）；
- 供电：`AVDD/IOVDD/DRVDD` = 3.3V、**`DVDD` = 1.8V**（数字核；接 3.3V 时驱动报
  `Too high supply voltage(s)`）；
- 模块：`snd-soc-tlv320aic3x` + `snd-soc-tlv320aic3x-i2c`（写在 `/etc/microduck-modules`，
  由 `microduck-wifi` 在开机时 modprobe）；
- 开机由 `microduck-audio.service` 执行 `microduck-audio-init`，打开
  DAC→HP/Line 与 Line/Mic2→PGA→ADC 通路（默认 mixer 全关，不设就"能放能录但没声"）。

自检：

```
microduck-audio            # 列声卡 / 设备 / mixer
microduck-audio play       # 440Hz 正弦 2s（左右声道）
microduck-audio rec 5      # 录 5s → /tmp/mic.wav
microduck-audio loop 5     # 录 + 回放，验证 mic 与输出通路
```

已知噪声：启动日志里的 4 条 `sound-mach: simple_dai_link_of failed` 来自未启用的
`sndi2s1/2/3` 与 `sndowa`，与 `microduck-audio` 无关，可忽略。

## 已知限制 / 待办## 已知限制 / 待办

- **蓝牙未通**：`aic_btusb` 需要 class `e0` 的 USB 接口，而 FCU760K 只有 1 个 `ff/ff/ff`
  接口（WiFi/BT 共用），且这个设备被 `aic8800_fdrv` 独占。后续要验证 BT 到底走
  USB 复用、UART（BSP 里有 `aic8800_btlpm`）还是其它通路，再决定接法。
- **蓝牙待接**：WiFi 起来后设备是 `8d81`（3 接口：BT `0xE0/0x01/0x01`、SCO、WiFi `0xFF/0xFF/0xFF`），
  还需要 `aic_btusb`（Radxa 包里的独立模块，编译需 BlueZ 分支的适配）才能出 `hci0`。
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
## 镜像体积

400 MB → 271 MB：pack 尺寸公式 + `resize2fs -M` + `-m 0`（−110 MB）、
`ROOTFS_TINY=y` 去 apt/hwdb/perl（−40 MB）、`MICRODUCK_MIN_MODULES=y` 裁其它平台模块
（−11 MB）。详见 [`docs/image-size.md`](../../docs/image-size.md)。
## NPU（VIPLite）

`A733_WITH_NPU=y`（默认）打开 `AW_NNA_VIP` + `NNA_VIP2`（需要 `CONFIG_DEBUG_FS` 和
`CONFIG_NPU_SET_CLK_VOL`，否则 vip2 编不过）；`A733_NPU_RUNTIME=y`（默认）用
`vendor/a733/npu/fetch-runtime.sh` 拉 ai-sdk、交叉编译 `vpm_run`，把
`/usr/lib/viplite`、`/usr/bin/vpm_run`、`/usr/share/npu`（LeNet）装进 rootfs，
板端跑 `/usr/sbin/microduck-npu`。参考 `jackhe183/radxa-dev`，详见
[`docs/npu.md`](../../docs/npu.md)。