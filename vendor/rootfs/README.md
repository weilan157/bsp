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
- `overlay/etc/systemd/system/fiq-getty.service` — 调试串口 login（ttyFIQ0）
- `overlay/etc/systemd/system/rockchip-partnames.service` — `/dev/block/by-name` 符号链接
- `overlay/etc/modprobe.d/autofs4-compat.conf` — systemd `autofs4` → 内核 `autofs`

## 额外软件包

编辑 `extra-packages.list`（每行一个包名）。
