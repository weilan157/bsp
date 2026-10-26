# 路线 A vs B：给 `weilan157/microduck` 软件栈选底座

先说数据：这套软件和 systemd/NetworkManager 的耦合有多深（在仓库里数出来的）：

| 指标 | 数量 |
|---|---|
| 交付的 systemd 单元 | 10 个（configd、btd、updaterd、robot-boot-check.timer、robotd、padd、tofd、mediad、nfcd） |
| `systemctl` 引用（脚本/代码/文档） | 317 处 |
| journald / `journalctl` 引用 | 111 处 |
| NetworkManager / nmcli / D-Bus 引用 | 255 处 |
| sysusers.d（robot 用户/组） | configd、btd 各自带 |
| updater | 完全按 systemd 设计：按 release 里的 unit 推导重启集合、boot-check timer、失败回滚 |

这不是“把服务换成 init 脚本”那么简单，是把**服务管理 + 日志 + 配网 + 更新**四层一起换掉。

## 一张表

| 维度 | A：BSP 出 product 镜像（Debian 13 + systemd + NM + GStreamer） | B：把软件改成 sysvinit 极简 |
|---|---|---|
| 改动重心 | BSP（rootfs profile、内核选项） | 软件仓库（10 个服务、日志、配网、更新器） |
| 软件侧改动 | 少量：`board.rs` 加 A733、`robotd.toml` 端口、VIPLite 后端、cedar 媒体 | 大量：重写服务管理/日志/更新；NM 换成 wpa_supplicant |
| 工作量（估） | 10–15 人日（含 NPU/媒体适配） | 15–30 人日，且大部分是重复劳动 |
| 与上游关系 | 基本不用 fork，release/updater 原样可用 | 永久 fork；每个上游 release 都要重新移植 |
| 镜像体积 | +100–150 MB（systemd/NM/journald/GStreamer），271 → 约 380–420 MB | 保持 271 MB 左右（甚至更小） |
| 启动时间 | systemd+NM 多 1–2 s（5 s 目标要看实测） | 快（sysvinit），但要自己保证服务顺序/重启 |
| 功能完整度 | `updaterd`、`robotctl`、journal、sysusers 直接可用 | 这些都要自己补，或者砍掉（就没有 OTA 了） |
| 风险 | 镜像变大、启动变慢；GStreamer/MPP→cedar 仍需改 | 改动面大、易漏（317 处 systemctl 引用）、回归难 |
| 可逆性 | 高：极简镜像继续保留，双 profile | 低：改完就和上游分叉，回不去 |
| 适合 | **产品要尽快跑起来、要 OTA、要跟上游** | 有强约束“不能有 systemd/体积必须 <300MB”，且愿意长期维护 fork |

## 子选项

- **A1**：Debian 13 + systemd + NetworkManager + GStreamer（最接近 Armbian 26.2）。
  上游 `deploy/` 几乎原样跑；镜像最大（约 400 MB+）。
- **A2**：Debian 13 + systemd + NM，**先不装 GStreamer**（mediad 用 `test` 视频源或
  软件编码），镜像约 330 MB；等视频链路（cedar/GStreamer）做完再加。
- **B1**：10 个 daemon 全部 sysvinit 化 + 文件日志 + 自研 updater。等于把上游四层重写一遍。
- **B2**：只保留 `robotd` + `padd`（控制环），其余（configd/updater/nfc/tof/mediad）不要，
  自己写一套最小服务。适合做“产品化裁剪”，但已经不是同一个软件栈。

## 推荐

**选 A，先 A2 再 A1**：

1. BSP 加 `ROOTFS_PROFILE=product`（Debian 13 + systemd + NM + udev + journald）；
2. 软件侧只做四件事：`board.rs` 加 A733 板型、`bus.port` 指 `/dev/microduck-servo`、
   `duck-detect` 换 VIPLite（或先 CPU `.onnx`）、`mediad` 换 V4L2/cedar；
3. 视频（GStreamer/webrtc）作为第二步加进来，不让它挡住“机器人先动起来”。

B 只在一种情况下更优：**产品硬性要求无 systemd/镜像 <300 MB，并且接受永久维护 fork**。
如果目标是“复刻机尽快能跑 + 以后还能跟着上游升级”，B 的隐性成本（每版移植 + 自研 OTA）
会远高于 A 多出来的 100 MB。

## 两条路都要做的事（不因选型而消失）

- `board.rs` / DT compatible 的 A733 条目；
- 舵机串口从 `/dev/ttyS2` 改到 `/dev/ttyS0`（或用我们加的 `/dev/microduck-servo` 别名）；
- NPU：RKNN → VIPLite（`/dev/vipcore`、`.nb`）；
- 摄像头：RKMPP → A733 的 VIN/cedar；
- IMU：原版 imu_to_dxl（串口总线）vs 复刻 HAT 的 I2C BMI088，二选一。
