# 泰山派 RK3566 设备树（vendor）

`rk3566-lckfb-tspi.dts` 是 LCKFB 泰山派 RK3566 的板级设备树，由 `./bsp sync dts`
同步到 `sources/kernel/arch/arm64/boot/dts/rockchip/`，并自动在 kernel 的
`Makefile` 里补 `dtb-$(CONFIG_ARCH_ROCKCHIP) += rk3566-lckfb-tspi.dtb`。

来源：上游 mainline 的 `rk3566-lckfb-tspi.dts`（Junhao Xie <bigfoot@classfun.cn>），
已按厂商 `develop-6.1` 内核的写法改写（combphy/USB3/HDMI 路由/regulator 命名）。
改动细节见文件头注释。

## 从泰山派 SDK 刷新（可选）

SDK 是 5.10 内核，dts 里会引用 SDK 自己的 dtsi/驱动；直接覆盖前请先对比。
需要时在 `config.env` 设置：

```bash
TSPI_DTS_SOURCE="/path/to/TaishanPi-Linux/kernel/arch/arm64/boot/dts/rockchip"
# 若 SDK 的板级文件还依赖 rk3566-linux.dtsi 之类，一并同步
DTS_EXTRA_FILES="rk3566-linux.dtsi"
```

然后 `./bsp sync dts && ./bsp kernel`。

## overlay

本分支未附带 dtbo overlay（`device-tree-overlays/` 为空则由 sync 跳过）。
需要时在 `vendor/dts/rockchip/device-tree-overlays/` 下新建并放 `overlays/*.dts`，
`ubootEnv.txt` 里用 `overlays=xxx.dtbo` 启用。
