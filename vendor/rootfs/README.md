# rootfs（Debian / microduck）

`ROOTFS_TYPE` 二选一，产物都是 `out/rootfs/` + `out/rootfs.ext4`：

| 值 | 内容 |
|----|------|
| `debian` | `debootstrap --variant=minbase` + systemd，功能完整 |
| `micro` | microduck 精简版：同一套 minbase，但用 **sysvinit** 启动（无 systemd），并加 ZRAM/开机扩容脚本、去掉文档/locale |

## Debian（默认）

| 项 | 默认 |
|----|------|
| 发行版 | `trixie`（Debian 13，可在 config.env 改为 `bookworm` 等） |
| 架构 | `arm64` |
| 变体 | `minbase`（官方最小根文件系统） |
| 镜像 | `out/rootfs/` 目录 + `out/rootfs.ext4` |

## micro（microduck）

- `micro/chroot-setup.sh`：装 busybox/sysvinit/wpa_supplicant/bluez/kmod/e2fsprogs，
  卸掉 systemd，清文档/locale；
- `micro/overlay/etc/inittab` + `init.d/rcS`：sysvinit 的 `sysinit` 只跑我们的脚本；
- `micro/overlay/usr/sbin/microduck-{zram,grow,wifi}`：ZRAM swap、resize2fs 扩容、
  后台连 WiFi；
- `micro/overlay/etc/fstab`、`wpa_supplicant.conf`、`usr/share/udhcpc/default.script`。

启动日志里会有一行 `microduck: userspace ready in Xs`，可用来量启动时间。

## overlay

- `overlay/etc/fstab` — 根分区用 **PARTUUID**（与 `parameter.txt` / 内核 `root=PARTUUID` 一致），并启用 `x-systemd.growfs`
- `overlay/etc/network/interfaces` — `wlan0` DHCP（板载 AP6212A）；`eth0` 为 USB 网卡预留
- `overlay/etc/wpa_supplicant/wpa_supplicant.conf` — WiFi 示例（改 ssid/psk）
- `overlay/etc/modules-load.d/bcmdhd.conf` — 开机加载 SDK 同款 `bcmdhd`（固件见 `vendor/firmware/ap6212/`）
- 默认启用 `systemd-timesyncd`（时间偏早会导致 `apt` 报 `Not live until`）
- `overlay/etc/systemd/system/fiq-getty.service` — 调试串口 login（ttyFIQ0）
- `overlay/etc/systemd/system/rockchip-partnames.service` — `/dev/block/by-name` 符号链接
- `overlay/etc/modprobe.d/autofs4-compat.conf` — systemd `autofs4` → 内核 `autofs`

## 额外软件包

编辑 `extra-packages.list`（每行一个包名）。当前只加了 `bluez`；
WiFi/BT 固件随 `./bsp rootfs` 从 `vendor/firmware/ap6212/` 安装，
不使用 Debian 的 `firmware-brcm80211`（与 SDK 的 bcmdhd 方案保持一致）。

> WiFi：`bcmdhd` 由 `/etc/modules-load.d/bcmdhd.conf` 开机加载，固件路径在
> `vendor/kernel-config/tspi-1m.config` 里写死，`wlan0` 应自动出现。
> 蓝牙：内核侧由 `wireless-bluetooth`（`bluetooth-platdata`）驱动上电，
> 还需要 SDK 的 `rk_hciattach`（或蓝点 `btattach -P bcm`）把 UART1 挂到
> `hci0`；这一步本仓库没有集成，需要时从 SDK 的 `external/rkwifibt` 编。
