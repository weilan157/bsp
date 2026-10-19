# 泰山派 RK3566 内核配置片段

编译前由 `./bsp sync config` 复制到 `sources/kernel/arch/arm64/configs/`，
再由 `KERNEL_DEFCONFIG_FRAGMENTS` 叠加到 `rockchip_linux_defconfig` 上。

| 文件 | 内容 | 何时生效 |
|------|------|----------|
| `bsp-boot.config` | Debian/systemd 启动所需的少量选项（autofs4 兼容等） | 默认 |
| `bsp-wifi.config` | AP6212（BCM43438）走 brcmfmac/bluez | 默认 |
| `tspi-vendor.config` | PANFROST、Mali Bifrost、GT9xx 触摸等 SDK 风格选项 | `TSPI_VENDOR_KERNEL_CONFIG=y` |

`rk3566.config` 由 rockchip-linux/kernel 自带，不需要放在本目录。

也可在 `config.env` 用 `KERNEL_EXTRA_FRAGMENTS` 指定其它 fragment 名（须已复制到 kernel configs 目录，或放在本目录并由 sync 脚本安装）。

从 SDK 刷新 fragment（可选）：

```bash
# config.env
TSPI_KERNEL_CONFIG_SOURCE="/path/to/SDK/kernel/arch/arm64/configs"
./bsp sync config
```
