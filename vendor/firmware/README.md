# 固件分区与打包

- `parameter.txt` — 泰山派 RK3566 GPT 分区表（Rockchip RK356x 通用布局）
- `package-file` — `update.img` 默认打包清单（无 recovery/oem/userdata 时可删对应行）

`rootfs` UUID `614e0000-0000-4b53-8000-1d28000054a9` 与 `vendor/rootfs/overlay/etc/fstab`、设备树 `chosen/bootargs` 一致。

WiFi/BT 固件不入库：板载 AP6212 由内核 `brcmfmac` 驱动，固件由 Debian 的
`firmware-brcm80211` 提供（见 `vendor/rootfs/extra-packages.list`）；若需
泰山派 SDK 的 `bcmdhd` 方案，请自行把固件放到 rootfs 的 `/lib/firmware/`。

打包工具（`afptool`、`rkImageMaker`）由 `./bsp pack` 自动安装，或 `./bsp tools pack`。
