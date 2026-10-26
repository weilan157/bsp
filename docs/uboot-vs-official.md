# 我们的 u-boot 和官方 u-boot 的差异 / DDR 初始化为什么慢

## 结论先说

- **源码是同一套**：`radxa/u-boot` @ `cubie-aiot-v1.4.6`（Allwinner 2018.07 + Radxa 改动）。
  我们**没有**改 u-boot 的功能代码，只改了构建配置和三处小修。
- 真正和官方镜像可能不同的地方是 **boot0 / boot_package 的来源与内容**：
  我们用 device 仓库里的**预编译 boot0** + `update_boot0` 注入 sys_config；
  官方 rsdk 的打包仓库（`radxa-pkg/u-boot-aw2501` + `awbs`）会带 `dramlib`/`spl-pub`
  等子模块，boot0 可能是**按 dramlib 现编**的。这一点会影响 DRAM 初始化的行为。
- **DDR “速率探测”在 boot0 里，不在 u-boot 里**。boot0 是预编译二进制，sys_config 里
  没有 `[dram_para]`（只有 platform/target/card/uart/jtag），所以改它要么换 boot0，
  要么用 brandy/dramlib 重编——**难度大、风险高，建议先放着**。能做的是把 boot0 的
  调试打印关掉、把其余启动阶段压一压。

## 我们和官方 u-boot 的具体差异

| 项 | 官方（rsdk / u-boot-aw2501） | 我们（`./bsp uboot`） |
|---|---|---|
| u-boot 源码 | `radxa/u-boot` 同一个分支 | 相同 |
| 构建架构 | AArch32（`MACH_SUN60IW2` 选 `CPU_V7A`） | 相同（`ARCH=arm` + `arm-linux-gnueabi-`） |
| 默认 DT | `sun60iw2p1_a733_defconfig` 里是参考板 `soc-system`，打包时换成 A7Z | 一样：`sed CONFIG_DEFAULT_DEVICE_TREE="sun60i-a733-cubie-a7z"` |
| 板级 dts 来源 | `device-a733/configs/cubie_a7z/uboot-board.dts`（submodule） | 相同（符号链接成 `device-a733`） |
| GCC 新告警 | 打包仓库 `Makefile.local` 用 `EXTRA_CFLAGS` 降级 | 相同（`-Wno-attributes` 等） |
| boot0 | 可能由 `awbs`+`dramlib` 现编，或直接用预编译 bin | **device 仓库的预编译** `boot0_sdcard_sun60iw2p1.bin`，`update_boot0` 注入 sys_config（SD + UFS 两份） |
| BL31 | `device/bin/bl31.bin` | 相同 |
| boot_package | `dragonsecboot -pack`，含 u-boot + monitor +（ARISC/SCP） | 相同命令；**只有找到 `scp*.bin` 才打 ARISC**，目前没有 → 包里没有 SCP |
| NOR 方案 | 有 `boot_package_nor.cfg` | 不做（只做 SD/eMMC/UFS） |
| 本地补丁 | — | ① `pmic_bus.h` 的 `_SUNXI_PMIS_BUS_H` 拼写修复；② 清掉 0 字节的 `sunxi_challenge.c`；③ `CONFIG_CONS_INDEX`（仅当 `A733_DEBUG_UART` 打开）；④ `debug_mode=0`（仅生产） |
| 产物 | u-boot + boot0 + boot_package（rsdk 组 GPT 镜像） | 相同四件套，`./bsp pack` 组 GPT 镜像 |

一句话：**运行时行为应当一致**；差异集中在“boot0 是预编译还是现编”、
“boot_package 里有没有 ARISC/SCP”、“有没有 NOR 变体”。

## DDR 初始化耗时分析

### 时间花在哪

A733 的启动链：

```
BROM → boot0（含 DRAM 初始化）→ BL31 → u-boot → kernel
```

- DRAM 的初始化/训练在 **boot0** 里，由预编译的 dramlib 代码完成；
- u-boot 只读取 boot0 传过来的 DRAM 参数/大小，本身不做“速率探测”；
- sys_config.fex 里没有 `[dram_para]` 段，所以 boot0 用的是**二进制里内置的参数**；
- 如果内置参数和板子的内存颗粒不匹配，boot0 可能走“扫描/尝试多种频率”的慢路径；
  匹配的话就是一次固定训练（通常几百毫秒）。

### 为什么不好改

| 想做的事 | 难度 | 说明 |
|---|---|---|
| 在 sys_config 里加 `[dram_para]` | 中 | 只有 boot0 支持该段时才生效；参数必须和板载 LPDDR4/4x 颗粒完全对上，填错直接不启动 |
| 重编 boot0（brandy + dramlib） | 高 | 需要 Allwinner 的 brandy 工具链、`dramlib`/`spl-pub` 子模块和对应板级参数；我们仓库里只有预编译 boot0 |
| 换 LPDDR5 版 boot0 | 低但不适用 | device 仓库有 `*_lpddr5.bin`，A7Z 是 LPDDR4/4x，不能混用 |
| 关 boot0 调试打印 | **低** | `debug_mode=0`，省的是串口输出时间（115200 下每 KB 约 90 ms） |
| 压缩/裁剪 boot_package | 低 | 关掉不用的 item、去掉 ARISC（如果不用待机） |

### 建议

**先放着**，但做三件便宜的事：

1. **生产关 boot0 调试打印**：`./bsp uboot` 现在默认把 `debug_mode` 改成 0，
   需要看 boot0 日志时 `A733_BOOT0_DEBUG=y`；
2. **确认 boot0 与内存颗粒匹配**：如果串口日志里 boot0 反复打印 DRAM 频率/扫描，
   把那段日志发我，可以判断是“固定训练慢”还是“参数不匹配在扫描”；
3. **把时间花在别处**：u-boot `bootdelay` 已经是 0（next-dev 默认），kernel 已裁剪，
   rootfs 是 sysvinit，剩余大头是 boot0 的 DRAM 训练 + BL31，属于厂商二进制。

### 如果以后一定要动

- 路线 A：找 Radxa 要 **A7Z 对应的、带正确 `[dram_para]` 的 boot0**（或让他们确认
  device 仓库里那个 boot0 就是量产参数）；
- 路线 B：按 `u-boot-aw2501` 的方式把 `brandy-2.0`/`dramlib`/`spl-pub` 拉齐，
  用 `awbs` 现编 boot0，再调 DRAM 参数（参考 `archlinuxarm-a733` 的 PKGBUILD 布局）；
- 路线 C：如果只是想把启动时间做短，优先考虑 u-boot/内核阶段，不要碰 DRAM。
