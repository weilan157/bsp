# 固件分区与打包

- `parameter.txt` — 泰山派 1M RK3566 的 GPT 分区表，逐字取自 SDK
  `device/rockchip/.chips/rk3566_rk3568/parameter-buildroot-fit.txt`
  （`rootfs` 固定 12 GiB，`userdata` 用满剩余空间）
- `package-file` — `update.img` 默认打包清单
- `ap6212/` — 板载 AP6212A（BCM43438）的 WiFi/BT 固件，取自 SDK
  `external/rkwifibt` 的 `firmware/broadcom/AP6212A1/`：
  - `fw_bcm43438a1.bin`、`nvram_ap6212a.txt` → `/lib/firmware/`（bcmdhd）
  - `BCM4343A1.hcd` → `/lib/firmware/` 与 `/lib/firmware/brcm/`（bluez）

`rootfs` UUID `614e0000-0000-4b53-8000-1d28000054a9` 与 `vendor/rootfs/overlay/etc/fstab`、
设备树 `chosen/bootargs` 一致。

打包工具（`afptool`、`rkImageMaker`）由 `./bsp pack` 自动安装，或 `./bsp tools pack`。
