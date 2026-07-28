# boot 脚本（Ky X1）

对齐 [orangepi-build](https://github.com/orangepi-xunlong/orangepi-build) `boot-ky.cmd` / `bootenv/ky.txt`。

| 文件 | 说明 |
|------|------|
| `boot-ky.cmd` | U-Boot 脚本；相对上游仅：**无 uInitrd**、`rootdev` 空时用 PARTUUID |
| `orangepiEnv.txt` | 基线 env；`./bsp bootimg` 追加 `fdtfile` / `console=serial` 等 |

`rootdev`：

1. `./bsp pack` / `./bsp emmc` 写入 `rootdev=UUID=...`（官方做法）
2. 未设置时用启动介质 p2 的 `PARTUUID=`（防只刷 boot 时空 root）

**不要**写死 `/dev/mmcblk0p2`。`/etc/fstab` 用 UUID（eMMC 上不存在 SD 的 `mmcblk0p*`）。

无桌面加速启动：默认已合并 `vendor/kernel-config/slim.config`（关 DRM/无线/音频等）。
