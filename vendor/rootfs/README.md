# rockchip-bsp 官方 Debian 无桌面 rootfs

使用 `debootstrap --variant=minbase`，不依赖 SDK `live-build` / 桌面栈。

## 默认

| 项 | 默认 |
|----|------|
| 发行版 | `trixie`（Debian 13，可在 config.env 改为 `bookworm` 等） |
| 架构 | `arm64` |
| 变体 | `minbase`（官方最小根文件系统） |
| 镜像 | `out/rootfs/` 目录 + `out/rootfs.ext4` |

## overlay

- `overlay/etc/fstab` — RK3576 典型 rootfs UUID（与 SDK parameter.txt 一致）
- `overlay/etc/init.d/S02rockchip-partnames` — GPT 分区符号链接

## 额外软件包

编辑 `extra-packages.list`（每行一个包名）。
