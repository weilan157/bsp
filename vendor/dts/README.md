# 泰山派设备树（vendor）

从泰山派 SDK `kernel/arch/arm64/boot/dts/rockchip` 复制的板级文件，用于叠加到 GitHub `rockchip-linux/kernel`：

- `tspi-3m-rk3576*.dts` / `*.dtsi`
- `rk3576-linux.dtsi`（tspi 引用）
- `device-tree-overlays/`（dtbo 与 `ubootEnv.txt`）

由 `./bsp sync dts` 同步到 `sources/kernel/`。若 `config.env` 中设置了 `TSPI_DTS_SOURCE`，则优先从该 SDK 路径刷新。
