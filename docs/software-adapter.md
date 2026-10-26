# 和 `weilan157/microduck`（Pollen 软件栈）的适配评估

结论：**现在不能直接适配**。软件本身是 aarch64 + glibc 的 Rust daemon，架构上没问题，
但它假设的是一套 **Armbian + systemd 的 RK3566 机器人**，而我们这个 BSP 产出的是
**sysvinit 极简镜像**，并且几处硬件通路（舵机串口、IMU、NPU、摄像头编码）不一样。

## 一、软件栈的假设（来自仓库）

| 项 | 软件栈要求 | 出处 |
|---|---|---|
| 基础系统 | Armbian 26.2 / Debian 13（Trixie），glibc ≥ 2.31 | `.cargo/config.toml`、`scripts/board-test.sh` |
| 服务管理 | **systemd**（units、journald、sysusers.d、`systemctl` 操作） | `deploy/README.md` |
| 配网 | **NetworkManager**（configd 接管 wifi；netplan/systemd-networkd 要被替换） | `deploy/README.md` §network |
| 板卡识别 | DT compatible 表：`radxa,zero3w-aic8800ds2` / `pollen,microduck-beta` / `seeed,microduck` / `rockchip,rk3566` | `robotd-params/src/board.rs` |
| 舵机总线 | `/dev/ttyS2`，**和 imu_to_dxl 板共用同一条串口** | `deploy/robotd.toml` `[bus]` |
| NPU | **RKNN**：`librknnrt.so` + `duck_detect.rknn`，`scripts/setup-npu.sh` | `duck-detect/src/rknn.rs`、`robotd.toml` |
| 摄像头/视频 | GStreamer（webrtcsink）+ Rockchip MPP 编码 | CI 构建说明、`robotd.toml` 视频段 |
| 更新 | updaterd + 签名 release + `/opt/robot/daemon/releases/<ver>`（A/B 式） | `deploy/README.md`、`updater.toml` |

## 二、我们 BSP 的现状

| 项 | 现状 |
|---|---|
| 用户态 | Debian trixie minbase + sysvinit + busybox，**没有 systemd / NetworkManager / GStreamer / journald** |
| 舵机串口 | A733 的 UART0（PB9/PB10 = 40-pin 8/10）→ Linux 里是 **`/dev/ttyS0`**（DT aliases `serial0`） |
| IMU | 复刻 HAT 是 **I2C**（BMI088 0x19/0x68、VL53L5CX、AIC3104），不是 imu_to_dxl 串口板 |
| NPU | VeriSilicon **VIPLite**（`/dev/vipcore`、`.nb` 模型），不是 RKNN |
| 摄像头 | VIN + IMX219（模板，未上板验证）；编码用 cedar（内核侧），没有 MPP 用户态 |
| 启动/分区 | 单 GPT（config + rootfs），boot0/BL31/u-boot 在卡头，没有 A/B |
| DT compatible | `radxa,cubie-a7z` / `radxa,a733` / `arm,sun60iw2p1` —— 不在软件的板卡表里 |

## 三、兼容矩阵

| 能力 | 能否直接用 | 说明 |
|---|---|---|
| aarch64 + glibc 2.31+ | ✅ | 我们是 trixie（glibc 2.41），满足 floor |
| systemd 服务/日志/更新 | ❌ | 我们的镜像没有 systemd；`deploy/` 整条链路依赖它 |
| NetworkManager 配网 | ❌ | 我们用 wpa_supplicant + 自己的 `microduck-net` |
| `/dev/ttyS2` 舵机总线 | ⚠️ | 我们是 `/dev/ttyS0`，改 `robotd.toml` 或 `robotd --port` 即可 |
| imu_to_dxl（串口 IMU） | ❌ | 复刻 HAT 的 IMU 在 I2C；`pad-imu`/`robotd` 的 IMU 路径要改 |
| RKNN NPU | ❌ | A733 是 VIPLite；`duck-detect` 要换后端（或先用 CPU ONNX 兜底） |
| GStreamer + MPP 视频 | ❌ | 需要装 GStreamer，并把编码换成 cedar/V4L2 |
| 板卡参数表 | ❌ | `board.rs` 没有 A733 条目，识别会落到 unknown |
| updater（签名/A-B） | ❌ | 分区布局与 systemd 都不匹配 |

## 四、三条路线

### 路线 A（推荐）：BSP 增加一个 "product" 镜像 profile

保留现在的极简镜像，同时新增：

```bash
./bsp config ROOTFS_PROFILE=product   # 设想中的开关
./bsp rootfs && ./bsp pack
```

product profile = 我们的 kernel/DT/bootloader + **Debian 13 + systemd + NetworkManager +
GStreamer + udev**（接近 Armbian 26.2 的 userland），然后直接跑他们的 `deploy/`。

BSP 侧要做：

1. rootfs profile 支持（systemd 基础包、NM、GStreamer、GStreamer 插件、udev）；
2. 内核补 GStreamer 需要的插件/DRM/V4L2 选项（我们为了精简关了不少）；
3. 分区/OTA：如果想用 updaterd，需要 A/B 或至少给它一个可写的 `/opt/robot`（现在 rootfs 可写，可以先用单分区）；
4. udev 稳定别名（例如 `/dev/microduck-servo` → `ttyS0`），方便软件配置；
5. 板级参数：把 A733 的机型/compatible 告诉软件仓库（见下）。

软件侧只需改：

- `robotd-params/src/board.rs`：加 `allwinner,sun60iw2p1` / `radxa,cubie-a7z` 的板型和默认参数；
- `robotd.toml`：`[bus] port = "/dev/ttyS0"`（或 udev 别名）；
- `duck-detect`：把 `rknn.rs` 换成 VIPLite（dlopen `libNBGlinker`/`libVIPhal` + `.nb`），
  或者先用 `robotd.toml` 里允许的 CPU `.onnx` 跑；
- `mediad`：GStreamer pipeline 从 RKMPP 换成 A733 的 V4L2/cedar 编码；
- `pad-imu`：按复刻 HAT 的 BMI088（I2C）改，或改用 imu_to_dxl 板。

### 路线 B：把软件改造成 sysvinit 极简

需要重写服务管理（rcS 脚本）、日志、更新器、NetworkManager 依赖（用我们的
`microduck-net` 替代），工作量大、和上游分叉也越来越远，不建议。

### 路线 C：混合

BSP 出 product profile 的 kernel/DT + 极简镜像跑我们自己的一套；软件栈只在
开发/验证机上用 Armbian。适合“先让算法跑起来，产品再收敛”的节奏。

## 五、BSP 还能做什么（优先级）

1. **上板验证**（最高）：启动链、UART4 调试口、WiFi/BT、AP+STA、HAT I2C/I2S、PB2 关机键；
2. **摄像头**：确认 J5 的 TWI3/CSI/MCLK 引脚，打开 `A733_WITH_CAMERA=y` 出图；
3. **NPU 上板**：`/dev/vipcore` + `microduck-npu` 跑通 LeNet；再做 `duck_detect` 的 `.nb` 版本；
4. **product profile**（路线 A 的 BSP 部分）；
5. **5 秒启动**：先量 boot0/BL31/u-boot/kernel/init 各段，再决定要不要动；
6. **OTA/分区**：A/B 或给 updater 留出可写区；
7. **媒体链路**：cedar H.264 编码 + GStreamer 插件（如果要 WebRTC 视频）；
8. **瘦身下一刀**：coreutils→busybox、内核 gzip FIT；
9. **CI**：`./bsp hal` + 构建产物检查；
10. **文档**：udev 别名、板级参数、软件侧改动清单。
