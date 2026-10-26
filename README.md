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
├── bsp                      # 唯一构建入口（PLATFORM=rk3566 | a733）
├── config.env.example
├── vendor/
│   ├── dts/rockchip/        # SDK 的 tspi-rk3566-*.dts / *.dtsi（7 个文件）
│   ├── kernel-config/       # defconfig fragment（rk3566.config 由内核自带）
│   ├── fit/boot.its         # FIT boot.img 模板（对齐 SDK 的 boot.its）
│   ├── firmware/            # parameter.txt / package-file / ap6212 固件
│   ├── patches/             # u-boot 补丁
│   ├── rootfs/              # debootstrap overlay + chroot 配置（含 micro 精简版）
│   └── a733/                # Cubie A7Z：精简 kernel config + rootfs overlay
├── scripts/
│   ├── lib.sh               # 公共变量与工具函数
│   ├── mod-env.sh
│   ├── mod-sources.sh
│   ├── mod-uboot.sh
│   ├── mod-kernel.sh
│   ├── mod-rootfs.sh
│   ├── mod-pack.sh
│   └── mod-a733.sh          # A733：包装 Radxa 的 debian 打包流程
├── docker/                  # 编译环境镜像（A733）
├── out/                     # 产物（不入库）
└── sources/                 # 克隆的源码（不入库）
```

## 快速开始

```bash
cp config.env.example config.env   # 或 ./bsp config 自动创建
./bsp env                          # 主机依赖（需 sudo）
./bsp setup all                    # 克隆 u-boot / rkbin / kernel
./bsp uboot
./bsp kernel                       # → Image + tspi-rk3566-micro.dtb
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

## microduck：极致精简

本分支（`microduck-tspi-rk3566`）在 `rk3566` 的基础上做减法，目标：**5 秒内启动**，
只留 **板载 WiFi/BT（AP6212A）+ 音频（RK809/I2S）+ MIPI 摄像头（ISP/CIF/OV5695）**。

| 维度 | microduck |
|---|---|
| 内核配置 | 在 `rk3566.config + bsp-boot.config + tspi-1m.config` 之上再叠 `microduck-tiny.config` |
| 关掉的 | DRM/FB/GPU(Mali/Panfrost)、VPU/RGA/ISPP/AIISP/VPSS/HDMI-RX、USB、PCIe、以太网(gmac)、netfilter/IPv6、多余文件系统（btrfs/xfs/f2fs/ntfs/nfs/cifs/9p/overlay/squashfs…）、SCSI/ATA/NVMe、HID/输入设备、蓝牙多余 profile、FTRACE/KPROBES/BPF/KALLSYMS |
| 留下的 | `AP6XXX`(bcmdhd)、`CFG80211`、`BT_HCIUART`、`RFKILL_RK`、`SND_SOC_ROCKCHIP_I2S`+`SND_SOC_RK817`+`SND_SIMPLE_CARD`、`VIDEO_ROCKCHIP_ISP`+`CIF`+`PHY_ROCKCHIP_CSI2_DPHY`+`VIDEO_OV5695`、`ZRAM(lz4)`、ext4/tmpfs/devtmpfs、MMC/SDHCI、8250 串口 |
| 设备树 | `tspi-rk3566-micro.dts`：只 include `core` + `csi`，不含 HDMI/DSI/EDP/gmac |
| rootfs | `ROOTFS_TYPE=micro`：Debian minbase + **sysvinit**（无 systemd/udev）+ busybox |
| 启动 | `/etc/init.d/rcS` 只做挂载 + ZRAM；`bcmdhd/hci_uart/ov5695` 加载、WiFi、`resize2fs` 全在后台；`bootargs` 带 `quiet loglevel=3` |
| ZRAM | `/usr/sbin/microduck-zram`：内存的 1/2，lz4，开机 `swapon` |
| 开机扩容 | `parameter.txt` 里 `rootfs:grow`；`/usr/sbin/microduck-grow` 在后台 `resize2fs` |

```bash
cp config.env.example config.env
./bsp env && ./bsp all          # kernel 用 microduck-tiny.config，rootfs 用 micro
```

启动耗时这样看（rcS 会往 dmesg 打点）：

```bash
dmesg | grep microduck          # microduck: mounts done at 1.2s / zram at 1.3s / userspace ready in 1.4s
```

### 启动还能怎么更快

已做：

- `next-dev` 的 u-boot 默认就是 `CONFIG_BOOTDELAY=0`（SDK 自带的 u-boot 是 2，
  换 SDK u-boot 时记得改）；
- DT `chosen/bootargs` 加 `quiet loglevel=3`、去掉 `earlycon`；
- 内核关 `VT/VT_CONSOLE`、无 DRM/FB、无 systemd/udev；
- `rcS` 只做挂载 + ZRAM，`bcmdhd/hci_uart/ov5695` 加载、WiFi、`resize2fs` 全在后台；
- 计时锚点 `mounts done / zram / userspace ready` 都打进了 `dmesg`。

分阶段继续压（社区做法，按收益排序）：

| 阶段 | 做法 | 预期 |
|---|---|---|
| U-Boot | `bootcmd` 收敛成 `boot_fit`（跳过 `boot_android`/`bootrkp`/`distro_bootcmd` 扫描），关 `CONFIG_ANDROID_AVB`、`CONFIG_CMD_BOOT_ANDROID` | 100–300 ms |
| U-Boot | 按 [Rockchip Boot Time](https://opensource.rock-chips.com/wiki_Boot_Time) 的做法在 loader/U-Boot 阶段提 CPU 频率 | 100–300 ms（注意散热） |
| 内核 | `bootargs` 加 `initcall_debug`，看 `dmesg \| grep initcall` 找慢驱动；`driver_async_probe` / 减少 deferred probe | 视驱动而定 |
| 内核 | 生产镜像去掉 `CONFIG_FIQ_DEBUGGER` + `earlycon`，`loglevel=0` | 50–150 ms |
| 内核 | `Image.lz4` + FIT `compression = "lz4"`（eMMC 读速慢时收益明显） | 50–150 ms |
| 用户态 | busybox init 取代 sysvinit；去掉 getty/login（调试时再开） | 20–50 ms |
| 硬件 | 启动介质（eMMC/SPI-NOR）、DDR 频率 | 视硬件 |

测法：串口抓 u-boot 的 `Boot …` 时间点；内核侧 `initcall_debug` 后再看
`dmesg | grep microduck` 的差值。通用方法论可参考
[Bootlin 的 boot-time principles](https://github.com/bootlin/training-materials/blob/master/slides/boot-time-principles/boot-time-principles.tex)。

## Cubie A7Z（Allwinner A733）

同一个仓库里用 `PLATFORM=a733` 切到瑞莎 Cubie A7Z（A733 / sun60iw2p1）。
结构与 `rk3566` 分支对齐：**官方 u-boot + 官方内核 + 自定义裁剪 rootfs + 板级设备树**。

| 组件 | 上游 | 说明 |
|---|---|---|
| u-boot | `radxa/u-boot` @ `cubie-aiot-v1.4.6` | Allwinner u-boot 2018.07 + boot0/brandy（`sun60iw2p1_a733_defconfig`） |
| kernel | `radxa/kernel` @ `allwinner-aiot-linux-6.6` | 全志 6.6 BSP（6.6.98） |
| BSP | `radxa/allwinner-bsp` @ `cubie-aiot-v1.4.8` | `drivers/ve`（编解码）、`configs/linux-6.6/*.dtsi` |
| 设备树 | `radxa/allwinner-device` @ `device-a733-v1.4.8` | `configs/cubie_a7z/linux-6.6/board.dts`、`sys_partition.fex` |
| rootfs | 本仓库 `vendor/rootfs/micro` | sysvinit + busybox + ZRAM + 开机扩容 |

```bash
cp config.env.example config.env
./bsp config PLATFORM=a733
./bsp env          # 交叉链 / dtc / dosfstools / mtools / mkimage
./bsp setup        # 官方 u-boot、kernel 6.6、allwinner-bsp、allwinner-device
./bsp uboot        # 官方 u-boot + boot0
./bsp kernel       # 挂 bsp/、拼 A7Z dts、defconfig+microduck.config -> Image + dtb
./bsp rootfs       # micro 精简 rootfs
./bsp hal          # 检查 dtb 是否满足 HAT 的 BSP/HAL 基本要求
./bsp pack         # 按 sys_partition.fex 组 MBR 镜像
```

精简策略与 RK3566 一致（无显示/GPU/USB/以太网），但**保留视频编解码**：
`CONFIG_AW_VIDEO_ENCODER_DECODER` + `AW_VIDEO_KERNEL_DEC/ENC` + `VIDEO_RT_MEDIA`
（符号来自 `allwinner-bsp/drivers/ve/cedar-ve/Kconfig`）。

u-boot 的板级 dts 在 u-boot 源码里（`arch/arm/dts/sun60i-a733-cubie-a7z.dts`），
它 include 了 `device-a733/configs/cubie_a7z/uboot-board.dts`，`./bsp uboot` 会自动把 device 仓库挂成 `device-a733`。

HAT 适配的设备树在 `vendor/a733/dts/microduck-a7z.dtsi`：UART0=PB9/PB10、TWI7=PJ22/PJ23（400 kHz）、
I2S0=PB4/5/6/7/8 + TLV320AIC3104、关机检测 PB3，显示/HDMI 关掉。

镜像按 **rsdk 官方布局**（`RadxaOS-SDK/rsdk` 的 `image.jsonnet` + `configs/socs.json`，
a733 = `partition_table_type=gpt`、`firmware_type=u-boot`）：

| 区域 | 大小 | 内容 |
|---|---|---|
| 0..16 MiB | 16 MiB | **boot0 @128 KiB**、boot0_ufs @2064 扇区、**boot_package.fex @12 MiB** |
| p1 | 16 MiB | FAT16 `config`（rsdk 的 `/config`） |
| p2 | 32 MiB..末尾 | ext4 `rootfs`：内核/设备树/启动脚本在 `/boot`，系统按 `UUID=` 挂载 |

`boot.scr`（`/boot/boot.scr`）由 `./bsp pack` 用 `vendor/a733/boot.cmd` 生成：这颗
u-boot 的 `CONFIG_BOOTCOMMAND="run distro_bootcmd"`，但没有 `sysboot`/extlinux 支持，
所以 distro_bootcmd 是扫到分区里的 `/boot.scr` 再 `source` 它来启动内核；
`/boot/extlinux/extlinux.conf` 与 `/etc/kernel/cmdline` 仍按官方格式生成，便于以后
换成支持 extlinux 的 u-boot。

### Docker 编译

依赖固化在镜像里（等价于 `./bsp env`）：

```bash
docker build --network host -t microduck-a733 -f docker/Dockerfile .
docker run --rm --network host \
    -v "$PWD":/work -v /tmp/a733src:/work/sources -w /work microduck-a733 \
    bash -lc './bsp config PLATFORM=a733 && ./bsp setup && ./bsp kernel'
```

`out/a733/kernel/` 出 `Image` 和 dtb；细节见 `docker/README.md`。

### 实测：整条链到 SD 卡镜像（2026-10-23）

`env → setup → kernel → uboot → rootfs → pack` 全部跑通，产物：

| 文件 | 大小 | 说明 |
|---|---|---|
| `out/a733/kernel/Image` | 37 MB | 6.6.98-g61f3fe291c7a-dirty，defconfig + microduck.config |
| `out/a733/kernel/sun60i-a733-cubie-a7z.dtb` | 154 KB | cpp + dtc 单编（device 的 board.dts + 我们的 microduck-a7z.dtsi） |
| `out/a733/uboot/u-boot.bin` / `u-boot.dtb` | 1.2 MB / 40 KB | AArch32 u-boot，`model = "Radxa Cubie A7Z"` |
| `out/a733/uboot/boot_package.fex` | 1.3 MB | `dragonsecboot -pack` 打的 TOC1 包：`u-boot` + `monitor`(BL31) |
| `out/a733/uboot/boot0.bin` | 240 KB | `boot0_sdcard_sun60iw2p1.bin` 经 `update_boot0` 注入 `sys_config.bin`（DRAM/GPIO） |
| `out/rootfs.ext4` | 347 MB | micro rootfs + 929 个 `.ko` + `/boot` |
| `out/a733/a733-micro.img` | 379 MB | GPT：config@16 MiB + rootfs@32 MiB，可 dd 到 SD 卡 |

镜像自检：boot0 在 128 KiB（`eGON.BT0`）、boot0_ufs 在 2064 扇区、`boot_package.fex`
在 12 MiB（`sunxi-package` + magic `0x89119800`）、GPT 两个分区（`config` p1 @32768、
`rootfs` p2 @65536）、p1 是 FAT16、p2 的 `/boot` 里有 `Image`/dtb/`boot.scr`/
`extlinux.conf`，`/etc/fstab` 里的 `UUID=D24E-9102` 与 FAT 卷序列号、
`UUID=d24e9102-…` 与 ext4 UUID 都对得上。

#### 这次修的坑

1. **u-boot 是 AArch32**：`sun60iw2p1_a733_defconfig` 里 `CONFIG_MACH_SUN60IW2`
   选的是 `CPU_V7A`（不是 `CONFIG_ARM64`），必须
   `ARCH=arm CROSS_COMPILE=arm-linux-gnueabi-`；用 armhf 工具链会因为默认
   `-mfloat-abi=hard` 在 `-march=armv7-a` 下报 “architecture lacks an FPU”。
2. **`make -C <u-boot>` 不行**：u-boot 的 Makefile 以当前目录为 objtree，必须
   `cd` 进去，否则 `arch/arm/dts/...` 会解析到工作区根上（`dts/dt.dtb` 报
   `Couldn't open .../sun60i-a733-cubie-a7z.dtb`）。
3. **默认 DT 是参考板**：defconfig 里 `CONFIG_DEFAULT_DEVICE_TREE="sun60iw2p1-soc-system"`，
   要改成 `sun60i-a733-cubie-a7z`，否则 FDTGREP 阶段找不到 soc-system.dtb。
4. **GCC 11 的新告警**：老 u-boot 代码会踩 `attributes`、`address-of-packed-member`、
   `misleading-indentation` 等新告警；现在按官方打包仓库（`radxa-pkg/u-boot-aw2501`
   的 `Makefile.local`）的做法用 `EXTRA_CFLAGS="-Wno-attributes …"` 关掉。
5. **boot0 只是模板，必须注入 sys_config**：`device/bin/boot0_sdcard_*.bin` 出厂前要用
   `update_boot0 … SDMMC_CARD` 把板子的 `sys_config.bin`（DRAM 参数、GPIO）写进去；
   不注入就是错的 DDR 时序，BROM 跳过去直接死，**串口一个字都没有**（第一次上板
   就是这个现象）。`sys_config.fex` → `sys_config.bin` 用
   `tools/pack/pctools/linux/mod_update/script`。
6. **`boot_package.fex` 必须带 BL31**：这颗 u-boot 没有 build.sh/brandy，boot0 只认
   Allwinner 的 TOC1 包，而且包里要有 `u-boot` + `monitor`(BL31)，boot0 先跳 BL31
   再跳 u-boot。现在用官方 `dragonsecboot -pack` 生成（`./bsp uboot` 会稀疏克隆
   `gitlab.com/tina5.0_aiot/lichee/tools`，默认放 `sources/a733/awtools`）。
7. **分区表/启动方式和官方对齐**：原来照板厂 `sys_partition.fex` 做 MBR
   （boot-resource/env/boot/rootfs/private），与 rsdk 不一致。现在按 rsdk 的
   `image.jsonnet` + `socs.json`（a733：GPT / u-boot）出 **GPT**：p1 `config` FAT
   16 MiB、p2 `rootfs` ext4 从 32 MiB 起；内核不再放独立 boot 分区，和官方一样
   放在 rootfs 的 `/boot` 下，`root=` 用 `UUID=`。
8. **启动脚本**：这颗 u-boot 没有 `CONFIG_CMD_SYSBOOT`（源码里也没有
   `boot/extlinux`），rsdk 的 extlinux 路径在这里走不通；`pack` 因此生成
   `/boot.scr` 给 `distro_bootcmd` 扫描 → `source`，同时仍按官方格式写
   `extlinux.conf` 和 `/etc/kernel/cmdline`。
9. **模块装不进 rootfs**：`install_kernel_modules` 只认 `sources/kernel` +
   `out/kernel/Image`，A733 两者都不同；新增
   `rootfs_install_platform_modules` hook，`./bsp rootfs` 会把 A733 模块
   `modules_install` + `depmod` 进 rootfs。
10. **`AW_INPUT_SENSORINIT` 编不过**：`bsp/drivers/input/init-input.ko` 引用未导出的
    `irq_to_desc`，modpost 报 `undefined!`；microduck 本来不要输入设备，已关掉。

> 仍未验证：修完 boot0 注入和 BL31 后的真机启动（上一版是**完全无输出**的），
> 以及 `/boot.scr` 里 `load mmc 0:2` 的实机启动。依据与状态见 `vendor/a733/README.md`。

### 配网 / SSH / 手柄（产品体验）

设计评审与改进方案见 [docs/ux-network-gamepad.md](docs/ux-network-gamepad.md)。
最小镜像（micro rootfs）里已经带上便于现场排查的一套：

- `microduck-net`：多 WiFi profile，`scan / add <SSID> <PSK> / list / switch <SSID> /
  forget / status / auto`，换网不用重刷镜像；
- `microduck-ip`：一条命令列出 wlan0/usb0/eth0 的地址和当前 SSID（SSH 排查用）；
- `sshd` + `avahi` 默认开：`ssh root@<hostname>.local`，主机名默认 `microduck`；`microduck-bt` 常驻 bluetoothd 并自动配对/回连 Xbox 手柄；`microduck-ap` 可开 AP+STA（`ap.conf` ENABLED=1）做 captive portal；
- `microduck-pad` + `90-microduck-pad.rules`：手柄（USB/蓝牙都算）插拔时写
  `/run/microduck/pad.json` 并尝试拉起 `robotd`，产品层据此进入可操控/急停。

配网/换网要“傻瓜式”的关键（AP 先起、每台独立 SSID/PSK、captive portal、蓝牙手柄回连、
断开急停）属于产品镜像层，方案和优先级都在那份文档里。
### 板级相关配置（与 SDK 对齐）

| 配置 | 默认值 | 对应 SDK |
|------|--------|----------|
| `UBOOT_BOARD` | `rk3566` | `./make.sh rk3566`（`RK_UBOOT_SPL=y`） |
| `UBOOT_LOADER_PATTERN` | `rk356x_*loader_*.bin` | make.sh `--spl-new` 产物 |
| `KERNEL_DEFCONFIG_FRAGMENTS` | `rk3566.config bsp-boot.config tspi-1m.config microduck-tiny.config` | `rockchip_linux_defconfig` + LCKFB 增量 + microduck 精简 |
| `KERNEL_DTS_NAME` | `tspi-rk3566-micro` | microduck 精简 dts（无显示/以太网） |
| `DTS_FILES_GLOB` | `tspi-rk3566-*` | dts + 6 个 dtsi 一起同步 |
| `parameter.txt` | `vendor/firmware/parameter.txt` | `parameter-buildroot-fit.txt` |

### 内核版本

| | 版本 | 说明 |
|---|---|---|
| 泰山派 SDK | **6.1.141** | `rk/kernel-stable`，tag `linux-6.1-stan-rkr7`，其上 4 个 LCKFB “适配泰山派1M” 提交 |
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

### rootfs（ROOTFS_TYPE）

产物：`out/rootfs/` 与 `out/rootfs.ext4`。

| 值 | 说明 |
|----|------|
| `debian` | 官方 debootstrap minbase + systemd，功能完整 |
| `micro`（本分支默认） | microduck 精简：sysvinit + busybox，无 systemd/udev，带 ZRAM 与开机扩容 |

两种都用 Debian 13 (trixie)；主机 debootstrap 过旧时 `./bsp config DEBIAN_RELEASE=bookworm`。

AP6212A（BCM43438，SDK 同款 `bcmdhd`）：`./bsp rootfs` 会把
`vendor/firmware/ap6212/` 的 `fw_bcm43438a1.bin`、`nvram_ap6212a.txt`、`BCM4343A1.hcd`
装进 `/lib/firmware/`。`debian` 用 `/etc/modules-load.d/bcmdhd.conf` 开机加载；
`micro` 在 `rcS` 里 `modprobe bcmdhd` 并在后台拉起 `wpa_supplicant`（配好
`/etc/wpa_supplicant/wpa_supplicant.conf` 的 SSID 才会连）。

### 从 SDK 刷新设备树

```bash
# config.env
TSPI_DTS_SOURCE="/path/to/sdk/kernel/arch/arm64/boot/dts/rockchip"
./bsp sync dts
./bsp kernel
```

`DTS_FILES_GLOB=tspi-rk3566-*` 会把 SDK 的 7 个板级文件一起同步，并在内核
`Makefile` 里补 `dtb-$(CONFIG_ARCH_ROCKCHIP) += tspi-rk3566-micro.dtb`。

## 编译产物

| 命令 | 产物 |
|------|------|
| `./bsp uboot` | `sources/u-boot/uboot.img`、`rk356x_*loader_*.bin` |
| `./bsp kernel` | `out/kernel/Image`、`out/kernel/tspi-rk3566-micro.dtb` |
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
- `rk3566`：泰山派 1M RK3566（完整功能）
- `microduck-tspi-rk3566`：在 rk3566 基础上做极致精简（5s 启动、ZRAM、开机扩容）
- `cubie-a7z-a733`：**本分支**，Cubie A7Z（Allwinner A733），同样精简 + 视频编解码

## 在 WSL2 / Ubuntu 22.04.5 上的实测（2026-10-20）

整条链路已在本机跑通：`env → setup → uboot → kernel → bootimg → rootfs → pack`。

| 项 | 值 |
|---|---|
| 主机 | Ubuntu 22.04.5 LTS (WSL2, kernel 6.18.54.1-microsoft-standard-WSL2)，8 vCPU / 7.2 GiB |
| 工具链 | gcc / aarch64-linux-gnu-gcc 11.4.0、binutils 2.38、dtc 1.6.1、debootstrap 1.0.126 |
| 源码 | u-boot `next-dev` / rkbin `master` / kernel `develop-6.1`（6.1.172） |
| 耗时 | u-boot ~40 s；内核 `Image`+dtb **11 min 21 s**（563% CPU）；rootfs ~10 min；`update.img` ~15 s |
| 产物 | `Image` 40 MB、dtb 165 KB、`boot.img` 41 MB、`rootfs.ext4` 436 MB（160 个 `.ko`）、`update.img` 482 MB |

产物文件名与分区地址已核对：`boot@0x8000`、`misc@0x6000`、`uboot@0x4000`、
`rootfs@0x78000`，与 `parameter.txt` 的 `CMDLINE` 一致；`rkImageMaker -unpack`
和 `afptool -unpack` 都能正常解开 `update.img`。

### 这次踩到的四个坑（脚本已修）

1. **GitHub 直连不通**：`git clone` 卡死、`cdn.jsdelivr.net` 直接 reset。改在
   `config.env` 里给三个仓库加 `https://ghfast.top/` 前缀即可；打不开
   jsdelivr 时 `PACK_TOOLS_DOWNLOAD_MIRRORS` 也换成 ghfast 的 raw 地址。
   这些都是本机配置，别写进 `config.env.example` 默认值。
2. **`--spl-new` 在 u-boot `next-dev` 里已删除**：`make.sh` 会把它当 defconfig 名，
   报 `ERROR: No configs/--spl-new_defconfig`。`mod-uboot.sh` 现在先
   `grep -- '--spl-new' make.sh`，只有老 SDK 的 u-boot 才传这个参数；新版
   loader 直接由 rkbin 的 `RK3566MINIALL.ini` 打出
   （`rk356x_loader_v1.26.114.bin`，471 KB）。
3. **jammy 自带的 `debian-archive-keyring` 2021.1.1 太旧**，debootstrap 装
   trixie 会在 `Checking Release signature` 报
   `Release signed by unknown key (key id 762F67A0B2C39DE4)`。`./bsp env` 和
   `./bsp rootfs` 都会检查，必要时从 Debian 镜像把 keyring 升到最新
   （`ensure_debian_keyring`）。
4. **`update.img` 芯片标识**：`RKBOOT/RK3566MINIALL.ini` 与 `RK3568MINIALL.ini`
   只差 DDR 参数（1056MHz / 1560MHz），`[CHIP_NAME] NAME=RK3568` 两文件相同，
   所以 rk356x 通用 loader 头部 21..24 字节是 `3568`，按它推 tag 会打出
   `-RK3568` 的固件。现在按 `UBOOT_BOARD` 取 `RK3566`（可用 `PACK_CHIP_TAG`
   覆盖），头里已是 `6653`（小端 3566）。

> 另外：next-dev 的 `make.sh` 没有 `--spl-new` 之后，loader 的 FlashBoot 用的是
> rkbin 预编译的 `bin/rk35/rk356x_spl_v1.14.bin`（SDK 的 `--spl-new` 会换成
> 自己编的 `u-boot-spl.bin`）。rk356x 一般不受影响；若真机卡在 loader 阶段，
> 换 SDK 的 u-boot（支持 `--spl-new`）再编一次。

**别在 `/mnt/d` 上直接编**：9p 文件系统上内核要几千次小文件读写，这里是
先 `rsync` 到 ext4（`/root/bsp`）再编、最后把 `out/` 拷回 Windows 侧的。

## 验证状态（已按 `repo sync` 后的 SDK 复核）

对同步后的 `extracted_sdk/`（kernel 6.1.141、u-boot、device/rockchip 均已是工作区）：

- **设备树**：`vendor/dts/rockchip/` 的 7 个文件与 SDK 树**内容一致**（SDK 里
  5 个 dtsi 是 CRLF，本仓库按 `.gitattributes` 统一为 LF，`tr -d '\r'` 后 diff
  为空）；在 SDK 自己的 `kernel-6.1` 树里用 `cpp` + `dtc` 预编译通过
  （`DTC_OK 101774 bytes`，仅 SDK 自身写法带来的常规告警）；对 GitHub
  `develop-6.1`（6.1.172）同样通过。
- **分区表**：`vendor/firmware/parameter.txt` 与 SDK 的
  `parameter-buildroot-fit.txt` 逐字相同。
- **板级名**：`KERNEL_DTS_NAME` 与 SDK BoardConfig 的
  `RK_KERNEL_DTS_NAME="tspi-rk3566-user-v10-linux"` 一致。
- **引导链**：SDK 用 `RK_UBOOT_SPL=y` → `./make.sh rk3566 --spl-new`，产物名取自
  rkbin 的 `RKBOOT/RK3566MINIALL.ini`：新版 rkbin 是
  `rk356x_loader_v1.26.114.bin`，SDK 自带的 rkbin 是
  `rk356x_spl_loader_v1.25.114.bin`，都不是 `rk3566_spl_loader_*`；
  `mk-loader.sh` 用 `u-boot/*_loader_*.bin` 匹配。本分支的
  `UBOOT_LOADER_PATTERN` 已相应改成 `*_loader_*.bin`（之前写成
  `rk3566_spl_loader_*.bin`，会导致 `./bsp pack` 找不到 loader）。
  GitHub u-boot `next-dev` 里也有同样的 `configs/rk3566.config`，但**没有**
  `--spl-new` 这个子命令（见上一节第 2 条）。
- **内核配置增量**：与 SDK 的 `rockchip_linux_defconfig` 逐行比对，SDK 多出的
  板级项只有 `BCMDHD_FW_PATH/NVRAM_PATH`、LED triggers、
  `USB_NET_CDC_MBIM/QMI_WWAN`、`LTE(+RM310)`、`MALI_BIFROST`、`GT9XX`；
  前四类已在 `tspi-1m.config`，LTE 需 SDK 的 `drivers/net/lte` 源码所以未开，
  Mali/GT9xx 放在可选的 `tspi-vendor.config`。
- **IO 电源域**：dts 里 `vccio4`/`vccio6` 接 `vcc_1v8`（1.8V），其余
  `pmuio2`、`vccio1/5/7` 接 3.3V，与 SDK 文档“除 VCCIO4/6 外都选 3V3”一致，
  编译期不需要 whiptail 交互。
- **PARTUUID**：dts 的 `root=PARTUUID=614e0000-0000` 用前缀匹配，内核
  `devt_from_partuuid()` 原生支持截断 UUID，和 `parameter.txt` 的
  `uuid:rootfs` 对应。
- `./bsp` 脚本 `bash -n` 通过；`./bsp sync dts` 实测同步 7 个文件并在内核
  `Makefile` 里幂等追加 `tspi-rk3566-micro.dtb`。

仍未覆盖：真机启动与烧写验证（`update.img` 只做了 `rkImageMaker/afptool`
解包自检）；开机画面无 `logo.bmp`（`resource.img` 只含 dtb）；蓝牙需要 SDK 的
`rk_hciattach` 才能把 AP6212A 挂到 `hci0`（本仓库只装固件和 `bluez`）。

## microduck 验证状态

- **内核配置**：在 SDK 的 `kernel-6.1`（6.1.141）树上跑
  `rockchip_linux_defconfig + rk3566.config + bsp-boot.config + tspi-1m.config + microduck-tiny.config`
  再 `olddefconfig`，结果符合预期：`DRM/FB/USB/PCI/IPv6/NETFILTER` 关闭，
  `VIDEO_ROCKCHIP_ISP/CIF + PHY_ROCKCHIP_CSI2_DPHY + VIDEO_OV5695`、
  `SND_SOC_RK817/I2S + SND_SIMPLE_CARD`、`AP6XXX + BT_HCIUART + RFKILL_RK`、
  `ZRAM(lz4)`、`CMA 64MB` 打开。
- **设备树**：`tspi-rk3566-micro.dts` 在 SDK 树上 `cpp + dtc` 通过（99432 字节
  dtb），不含 HDMI/DSI/EDP/gmac 的 include。
- **rootfs**：WSL 里用 `ROOTFS_TYPE=micro` 实测构建通过——sysvinit 做 init、
  我们的 `inittab/rcS/fstab` 生效、`btattach`、`wpa_supplicant`、`resize2fs`
  都在；`out/rootfs` 约 175 MB、`out/rootfs.ext4` 约 265 MB（保留 `bluez` 的代价，
  去掉它可再省 ~40 MB）。
- **未验证**：真机上的 5 秒启动目标——需要上板量；`dmesg | grep microduck`
  会打印 userspace ready 的时间点。

## 远程仓库

```bash
git remote add origin git@github.com:weilan157/bsp.git
git push -u origin microduck-tspi-rk3566
```
