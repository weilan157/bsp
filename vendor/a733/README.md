# Cubie A7Z（Allwinner A733 / sun60i）

本目录是 `PLATFORM=a733` 用的配置层，构建本身**复用 Radxa 官方的 Debian 打包仓库**，
不重写 Allwinner longan 流程。

## 上游

| 组件 | 仓库 | 说明 |
|---|---|---|
| kernel | https://github.com/radxa-pkg/linux-a733 | debian 打包仓库；submodule：`radxa/kernel`（`allwinner-aiot-linux-5.15`）+ `radxa/allwinner-bsp` + `radxa/allwinner-device` |
| u-boot | https://github.com/radxa-pkg/u-boot-aw2501 | 含 boot0/SPL：submodule `radxa/u-boot` + Allwinner 的 `tools`/`arisc`/`dramlib`（gitlab tina5.0_aiot） |
| 镜像 | https://github.com/RadxaOS-SDK/rsdk | Docker/Dev Container 里的 `rsdk` TUI，产出 `output.img`，主板选 `radxa-a733` |

板级 dts：`sun60i-a733-cubie-a7z.dtb`（Radxa 的 `debian/patches/linux/0004-*` 里加的）。

## 本仓库加了什么

- `microduck.config`：叠在 `defconfig + radxa.config` 之上的**精简配置**：
  - 保留：**视频编解码**（`CONFIG_AW_VIDEO_ENCODER_DECODER` + `AW_VIDEO_KERNEL_DEC/ENC` +
    `VIDEO_RT_MEDIA`）、音频、摄像头、WiFi/BT、ZRAM；
  - 去掉：DRM/FB/GPU、USB、PCIe、以太网、netfilter/IPv6、多余文件系统、调试设施。
  - 编解码符号来自 `allwinner-bsp/drivers/ve/cedar-ve/Kconfig` 与
    `allwinner-bsp/drivers/rt-media/Kconfig`，已核对。
- `overlay/`：给 micro rootfs 用的 A733 版本 —— console 改 `ttyS0,115200`，
  模块清单改成让用户按板载 WiFi 芯片填写（`/etc/microduck-modules`）。
- `scripts/mod-a733.sh`：`./bsp env/setup/kernel/uboot/rootfs/os` 的包装。

## 内核 6.6（全志官方最新）

全志 v1.4.8 已经同时提供 6.6 的板级文件，所以「A7Z 设备树 + 最新内核」是官方组合，
不是硬凑：

| 文件 | 来源 |
|---|---|
| `sun60i-a733-cubie-a7z.dts` | `allwinner-device@device-a733-v1.4.8` 的 `configs/cubie_a7z/linux-6.6/board.dts` |
| `sun60iw2p1.dtsi` 等 SoC dtsi | `allwinner-bsp@cubie-aiot-v1.4.8` 的 `configs/linux-6.6/*.dtsi` |
| 内核 | `radxa/kernel@allwinner-aiot-linux-6.6`（6.6.98） |

6.6 的内核顶层 Makefile 自带 `drivers-y += bsp/` 与 `-I$(srctree)/bsp/include`，
所以把 `allwinner-bsp` 放到内核树根的 `bsp/` 就能编进 `drivers/ve`（cedar-ve）、
`drivers/rt-media` 等 BSP 驱动。

**已实测**：在 6.6 的 `dts/allwinner` 里放入 `board.dts` + BSP 的
`sun60iw2p1.dtsi`/`sun60iw2p1-cpu-vf.dtsi`，用 6.6 的 `include` 加 BSP 的
`include` 做 `cpp + dtc`，**编译通过**（156365 字节 dtb，含 `ve@`、`codec` 节点）。

```bash
./bsp config PLATFORM=a733
./bsp config A733_KERNEL_VERSION=6.6
./bsp env && ./bsp setup     # 拉 kernel 6.6 + bsp v1.4.8 + device v1.4.8
./bsp kernel                 # 自动装 bsp/、拼 dts、defconfig+microduck.config、出 Image+dtb
```

与 5.15 路线的区别：6.6 不产 deb，产物是 `out/a733/kernel/{Image,*.dtb}`；
u-boot/boot0 与内核版本无关，仍走 5.15 的打包仓库。

## 用法

```bash
cp config.env.example config.env
./bsp config PLATFORM=a733
./bsp env          # 装 build-essential / aarch64 交叉链 / debhelper 等
./bsp setup        # clone linux-a733 + u-boot-aw2501（含 submodule，几 GB）
./bsp kernel       # defconfig + radxa.config + microduck.config -> linux-*_arm64.deb
./bsp uboot        # u-boot + boot0 -> u-boot-*_arm64.deb
./bsp rootfs       # microduck 精简 rootfs（sysvinit + busybox + ZRAM + 扩容）
./bsp os           # 提示用 rsdk 出 output.img（Docker）
```

## 状态（未在 A733 上验证）

本分支的 A733 部分是**参考 Radxa 文档搭的集成层**，以下未验证：

- 宿主机没有 Docker / A733 板子，`make build` 与 `rsdk` 都没有实际跑过；
- `u-boot-aw2501` 的 Makefile 目标按 `build`/`deb` 兼容处理，未在真仓库上确认；
- 板载 WiFi/BT 芯片的模块名（`aic8800_fdrv` / `bcmdhd` / `rtl8xxx` …）需要
  拿到板子后 `ls /lib/modules/$(uname -r)/kernel/drivers/net/wireless/` 确认；
- 镜像分区/启动参数由 `rsdk` 决定，本仓库不重写。
