# rockchip-bsp 官方 Debian 无桌面 rootfs

使用 `debootstrap --variant=minbase`，不依赖 SDK `live-build` / 桌面栈。构建：`./bsp rootfs`。

## 默认

| 项 | 默认 |
|----|------|
| 发行版 | `trixie`（Debian 13，可在 config.env 改为 `bookworm` 等） |
| 架构 | `arm64` |
| 变体 | `minbase`（官方最小根文件系统） |
| 镜像 | `out/rootfs/` 目录 + `out/rootfs.ext4` |

## overlay

- `overlay/etc/fstab` — 根分区用 **PARTUUID**（与 `parameter.txt` / 内核 `root=PARTUUID` 一致），并启用 `x-systemd.growfs`
- `overlay/etc/network/interfaces` — `wlan0` DHCP（板载 AP6212）；`eth0` 为 USB 网卡预留
- `overlay/etc/wpa_supplicant/wpa_supplicant.conf` — WiFi 示例（改 ssid/psk）
- `overlay/etc/modules-load.d/brcmfmac.conf` — 开机加载 AP6212 的 brcmfmac（固件来自 `firmware-brcm80211`）
- 默认启用 `systemd-timesyncd`（时间偏早会导致 `apt` 报 `Not live until`）
- `overlay/etc/systemd/system/fiq-getty.service` — 调试串口 login（ttyFIQ0）
- `overlay/etc/systemd/system/rockchip-partnames.service` — `/dev/block/by-name` 符号链接
- `overlay/etc/modprobe.d/autofs4-compat.conf` — systemd `autofs4` → 内核 `autofs`

## 额外软件包

编辑 `extra-packages.list`（每行一个包名）。当前默认装了
`firmware-brcm80211`、`bluez`（AP6212 的 WiFi/BT 固件与协议栈）。

> `brcmfmac43430-sdio.txt`（板级 NVRAM）不在 Debian 仓库内；若 WiFi 扫描不到
> AP，把泰山派 SDK / 厂商提供的 NVRAM 放到 `/lib/firmware/brcm/` 同名文件即可。
