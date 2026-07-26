# 泰山派 SDK 风格可选内核配置片段

由 `TSPI_VENDOR_KERNEL_CONFIG=y` 启用，编译前复制到 `sources/kernel/arch/arm64/configs/`。

| 文件 | 内容 |
|------|------|
| `tspi-vendor.config` | PANFROST、Mali Bifrost、GT9xx 触摸等 |

也可在 `config.env` 用 `KERNEL_EXTRA_FRAGMENTS` 指定其它 fragment 名（须已复制到 kernel configs 目录，或放在本目录并由 sync 脚本安装）。

从 SDK 刷新 fragment（可选）：

```bash
# config.env
TSPI_KERNEL_CONFIG_SOURCE="/path/to/SDK/kernel/arch/arm64/configs"
./bsp sync config
```
