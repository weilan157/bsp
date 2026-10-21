# 泰山派 1M RK3566 设备树（vendor）

7 个文件逐字取自泰山派官方 6.1 SDK 的 `kernel-6.1/arch/arm64/boot/dts/rockchip/`，
另外新增 microduck 用的精简 dts：

| 文件 | 作用 |
|------|------|
| `tspi-rk3566-user-v10-linux.dts` | 完整版主 dts（`rk3566` 分支），用户层：LED、耳机检测、UART3、I2C2/3、SPI3、PWM、红外 |
| `tspi-rk3566-micro.dts` | **本分支主 dts**：只 include core + csi，不含 HDMI/DSI/EDP/gmac |
| `tspi-rk3566-core-v10.dtsi` | 核心板：电源/PMIC、音频、SD/eMMC、USB、WiFi/BT platdata、按键等 |
| `tspi-rk3566-hdmi-v10.dtsi` | HDMI 输出（micro 不引用） |
| `tspi-rk3566-dsi-v10.dtsi` | MIPI-DSI 屏（默认注释，与 EDP 互斥） |
| `tspi-rk3566-edp-v10.dtsi` | EDP 屏（默认注释） |
| `tspi-rk3566-csi-v10.dtsi` | CSI 摄像头（ov5695） |
| `tspi-rk3566-gmac1-v10.dtsi` | 扩展板千兆网口（micro 不引用） |

`./bsp sync dts` 会按 `DTS_FILES_GLOB=tspi-rk3566-*` 把这些文件同步到
`sources/kernel/arch/arm64/boot/dts/rockchip/`，并自动在 kernel 的 `Makefile` 里补
`dtb-$(CONFIG_ARCH_ROCKCHIP) += tspi-rk3566-micro.dtb`。

这些文件与 `repo sync` 后的 SDK 树**内容一致**（SDK 里 5 个 dtsi 是 CRLF，
本仓库按 `.gitattributes` 统一为 LF），并已分别在 SDK 的 `kernel-6.1`
（6.1.141）与 GitHub `develop-6.1`（6.1.172）里用 `cpp` + `dtc` 预编译通过；
SDK 自带的写法会产生少量 `simple_bus_reg` / `graph_child_address` 告警，属正常。

IO 电源域与 SDK 文档一致：`vccio4`、`vccio6` 接 `vcc_1v8`（1.8V），
`pmuio2`、`vccio1`、`vccio5`、`vccio7` 为 3.3V，`vccio3` 为 SD 卡可变电压。

## 从 SDK 刷新

```bash
# config.env
TSPI_DTS_SOURCE="/path/to/sdk/kernel/arch/arm64/boot/dts/rockchip"
./bsp sync dts && ./bsp kernel
```

## overlay

SDK 额外提供 `device-tree-overlays/`（`Makefile` + `ubootEnv.txt`），依赖 SDK
u-boot 里的 `overlay_loader` 补丁从 `/boot/ubootEnv.txt` 动态加载 dtbo。
本仓库用的是 GitHub 官方 u-boot，没有该补丁，因此未收录；需要时把 SDK 的
overlay 目录和 u-boot 补丁一起移植进来。
