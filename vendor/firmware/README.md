# 固件分区与打包

- `parameter.txt` — 泰山派 RK3576 GPT 分区表（与 SDK `.chips/rk3576` 一致）
- `package-file` — `update.img` 默认打包清单（无 recovery/oem/userdata 时可删对应行）

`rootfs` UUID `614e0000-0000-4b53-8000-1d28000054a9` 与 `vendor/rootfs/overlay/etc/fstab`、设备树 `bootargs` 一致。

打包工具（`afptool`、`rkImageMaker`）见 `scripts/fetch-pack-tools.sh`。
