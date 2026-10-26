# UART 调试口 vs 舵机总线：怎么取舍

## 冲突是什么

Cubie A7Z 的 40-pin 排针：

| 脚 | 信号 | 用途 |
|---|---|---|
| 8 / 10 | **CPUX-TX / CPUX-RX = UART0（PB9/PB10）** | 官方调试串口；HAT 的舵机总线也接在这两个脚 |
| 3 / 5 | TWI7（PJ22/PJ23） | HAT I2C |
| 12/35/36/38/40 | I2S0 | HAT 音频 |
| 31 | PB2 | HAT 关机检测 |
| 7 / 11 | PB0 / PB1 | 原理图上没有分配给 HAT（可作调试口候选，需确认 pinmux） |

boot0 / BL31 / u-boot / kernel 默认都从 **UART0 @115200** 输出。舵机总线是
**单线半双工 TTL、1 Mbps**，由 HAT 硬件做方向切换——它不会把 SoC 的 UART 隔离出来，
所以 console 和舵机不能同时用 UART0：

- 波特率不同（console 115200 vs 舵机 1 Mbps），一边改动另一边就乱码/丢帧；
- 每次内核打印都会往舵机总线上灌字节，舵机可能误动作；
- HAT 的方向控制只对“它自己发”有效，对 SoC 的 console 输出不设防。

## 现在的配置（本分支）

- 设备树：`&uart0` 给舵机（PB9/PB10），`console` 从 UART0 移走；
- `boot.cmd`：`console=tty1 loglevel=3`；
- inittab：getty 在 `tty1`。

结果：**当前既没有串口 console，也没有显示**（A7Z 无 HDMI 接显示器时 tty1 看不到），
现场唯一入口是 SSH。这只能算“能用”，不算“好排查”——boot0/u-boot 起不来时没有任何输出。

## 四种方案对比

| 方案 | 全链路日志（boot0 起） | 需要额外硬件 | 改动量 | 适用 |
|---|---|---|---|---|
| **A. 调试口换到 UART2（7/11，PB0/PB1）** | ✅ | USB-TTL 一根 | 中：boot0 sys_config + u-boot stdout-path + kernel cmdline + DT pinctrl | 开发/产测/现场都能用 |
| **B. USB-C gadget 串口（ACM）+ RNDIS** | ❌（kernel 起来后才有） | 一根 USB-C 线 | 中：kernel USB gadget + DT peripheral + rootfs gadget 脚本 | 量产现场、无排针 |
| **C. 只用 SSH** | ❌ | 无 | 零 | 日常维护；救砖/产测不行 |
| **D. UART0 同时当 console 和舵机** | ✅ | 无 | 零 | **不要用**：波特率/方向冲突，会干扰舵机 |

## 推荐

**首选 A：把调试口换到 UART2（40-pin 7/11），UART0 永久留给舵机。**

理由：

- 只有 A 能在 **boot0/BL31/u-boot** 阶段就有日志——这正是“完全起不来”时最需要的；
- 不动物理 HAT，不动 8/10 的舵机线；
- 量产时 sshd/mDNS 照常，串口只作为兜底，不占启动时间。

实施清单（按顺序确认/修改）：

1. **确认 pinmux**：PB0 的复用里有 `UART2-TX`、PB1 是否有 `UART2-RX`（球图里 PB0 明确有
   UART2-TX；PB1 需要查 pinmux 表/原理图 GPIO 页）。确认 7/11 没有被 HAT 占用。
2. **device 树**（`board.dts` 覆盖层里加）：
   ```dts
   &pio { uart2_pins: uart2-pins { pins = "PB0", "PB1"; function = "uart2"; }; };
   &uart2 { status = "okay"; pinctrl-0 = <&uart2_pins>; };
   ```
3. **u-boot**：`uboot-board.dts` 的 `chosen/stdout-path` 改成 `serial2:115200n8`
   （或在 defconfig 里指定 console 索引）。
4. **boot0**：`sys_config.fex` 里把调试串口从 uart0 改成 uart2
   （字段名以 Tina 的 `[uart_para]` 段为准，常见是 `uart_debug_port`）。
5. **kernel cmdline**：`console=ttyS2,115200`（若驱动枚举成 `ttyAS2` 就改对应名字），
   量产可再配 `quiet loglevel=3`。
6. **验证**：拔掉 HAT，接 USB-TTL 到 7/11，从 boot0 到 login 全链路看日志；
   再插上 HAT，确认舵机总线 1 Mbps 正常、console 不干扰。

**次选 B（USB-C gadget）**：如果不想动排针/不想加 USB-TTL，或者机器装壳后只露出 USB-C，
用 gadget 串口 + RNDIS 做“一插即有 console + 网口”。缺点：拿不到 boot0/u-boot 日志。
实现要点：kernel 打开 `USB_GADGET/CONFIGFS/F_ACM/F_RNDIS`，DT 里对应 UDC 设
`dr_mode = "peripheral"`（或走 role-switch），rootfs 里 configfs 建 gadget，
`getty` 挂 `ttyGS0`，`usb0` 上跑 DHCP（10.55.0.1）。

**不建议只用 SSH**：SSH 依赖 WiFi/内核/sshd 全部正常；一旦起不来，现场没有任何输出，
只能拆机接 UART——这正是要避免的“折腾”。

**不要选 D**：console 与舵机共用 UART0 在时序和电平上都会互相干扰。

## 量产建议

- 出厂固件：UART0 给舵机、console 关闭（或按 A 方案放到 UART2）；
- SSH/mDNS 默认开，`microduck ip` 一条命令看地址；
- 产测夹具用 8/10 的 UART0（HAT 不插）做 boot0/u-boot 日志和舵机总线测试，
  两边共用同一对脚，测试时二选一。

## 待确认

- PB1 支持 UART2-RX（已由 pinmux 表确认）；但 pin 7 是 HAT 的 Stemma SDA，改用 UART4；
- HAT 是否占用 7/11；
- boot0 的 sys_config 里调试串口字段名/取值（Tina `[uart_para]`）。

## 方案 A 的可行性（按 A733 40-pin pinmux 表 + HAT 映射）

A733 的 40-pin 复用表里，可用于调试的 UART 有两组：

| 脚 | SoC | 复用（Function2） | HAT 侧 |
|---|---|---|---|
| 7 | PB0 | **UART2-TX** | **GPIO4 = Stemma/QT SDA（HAT 会用）** |
| 11 | PB1 | **UART2-RX** | GPIO17（HAT 未分配） |
| 16 | PJ24 | **UART4-TX** | GPIO23（HAT 未分配） |
| 18 | PJ25 | **UART4-RX** | GPIO24（HAT 未分配） |

结论：

- **UART2（7/11）在 pinmux 上可行**（PB0/PB1 的 F2 就是 UART2），但 7 脚在 HAT 上是
  Stemma/QT 的 SDA（GPIO4），接了 Stemma 外设就会打架——**不推荐**。
- **UART4（16/18，PJ24/PJ25）更干净**：HAT 的 GPIO23/24 没有功能分配，
  舵机/I2C/I2S/关机检测都不占这两脚。**推荐这个**。

## 已实现：`A733_DEBUG_UART`

```bash
./bsp config A733_DEBUG_UART=uart4     # 或 uart2 / none
./bsp kernel && ./bsp uboot && ./bsp pack
```

它会：

1. 设备树里生成 `microduck-debug-uart.dtsi`：`&uart4 { status = "okay"; pinctrl-0 = <&uart_debug_pins>; }`，
   引脚组 `PJ24/PJ25`、function `uart4`（uart2 则是 PB0/PB1）；
2. `boot0` 的 `sys_config.fex [uart_para]` 改成
   `uart_debug_port = 4`、`uart_debug_tx = port:PJ24<2>…`、`uart_debug_rx = port:PJ25<2>…`；
3. u-boot `.config` 设 `CONFIG_CONS_INDEX=5`（uart2 是 3）；
4. 打包时 kernel cmdline 用 `console=ttyS4,115200`（uart2 是 `ttyS2`，可用 `A733_CONSOLE` 覆盖）。

已验证（本机）：

- 带调试 dtsi 的 dtb 编译通过（157652 字节），`uart@2504000` 是 `status = "okay"`、
  `pinctrl-0` 指向 `PJ24/PJ25`，aliases 里有 `serial4`（对应内核 `ttyS4`）；
- `sys_config.fex` 改完是 `uart_debug_port = 4` + PJ24/PJ25 的 port 行。

还需要上板确认的：

- u-boot 在 `CONFIG_CONS_INDEX=5` 下是否真的把 console 输出到 UART4（u-boot 的
  引脚复用可能还要在它的 DT 里补 uart4 节点）；
- HAT 完整原理图确认 GPIO23/24 没有接到别的电路；
- 3.3V 电平的 USB-TTL（TX/RX 交叉、共地）。