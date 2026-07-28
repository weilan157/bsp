# boot 脚本（Ky X1）

对齐 [orangepi-build](https://github.com/orangepi-xunlong/orangepi-build) `external/config/bootscripts/boot-ky.cmd` / `bootenv/ky.txt`。

| 文件 | 说明 |
|------|------|
| `boot-ky.cmd` | U-Boot 脚本源；`root=${rootdev}`，无 uInitrd（`booti Image - dtb`） |
| `orangepiEnv.txt` | 基线环境（verbosity/bootlogo）；`./bsp bootimg` 追加 fdtfile 等 |

`rootdev`：

1. `./bsp pack` / `./bsp emmc` 写入 `rootdev=UUID=...`（对齐官方）
2. 若未设置，`boot-ky.cmd` 用启动介质 **p2** 的 `PARTUUID=`（eMMC/SD 均可，避免空 root）

默认 `verbosity=7`（`loglevel=7`），否则 earlycon 之后串口几乎无输出，易误判为卡死。

**不要**写死 `/dev/mmcblk0p2`。`/etc/fstab` 也必须用 UUID（eMMC 上 SD 的 `mmcblk0p*` 不存在会进维护模式）。
