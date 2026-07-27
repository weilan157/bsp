# boot 脚本（Ky X1）

| 文件 | 说明 |
|------|------|
| `boot-ky.cmd` | U-Boot 脚本源（无 initrd，`booti Image - dtb`） |
| `orangepiEnv.txt` | 运行时环境；`./bsp bootimg` 会追加 fdtfile/rootdev |

参考 orangepi-build `external/config/bootscripts/boot-ky.cmd`。
