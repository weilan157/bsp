# A2 但不装 NetworkManager：可行性与代价

## 结论

**可以。** BSP 侧只是“product profile 不装 NM”，继续用我们自己的
`wpa_supplicant + microduck-net + hostapd portal`；软件侧的 `configd` 会在拿不到
NetworkManager 的 D-Bus 时**自动降级**，不会退出。

关键代码（`configd/src/main.rs`）：

```rust
let net: Arc<dyn Net> = match backend(args.fake_net).await {
    Ok(net) => net,
    Err(e) => Arc::new(configd::net::UnavailableNet::new(e)),
};
```

`net.rs` 里 `UnavailableNet` 的注释也写明了这是有意设计：

> A `configd` that exits takes BLE provisioning down with it. That turns
> "wifi is unavailable" into "the robot cannot be reached at all".

所以没有 NM 时：

- `configd` 照常启动，BLE 配手柄、电源、日志、identity、indicator 都不受影响；
- 只有 wifi 那组 API（`status/scan/connect/forget`）返回 `Unavailable`
  ——手机 App 里的“给机器人配网”会显示不可用；
- 配网改用我们的 `/dev/microduck-servo` 那一套：开机 AP `duck-XXXX` + 网页配网
  （`microduck-ap` / `microduck-net`），SSH 仍然可用。

## 三种组合的量

| 组合 | 镜像 | 软件改动 | 手机 App 配网 |
|---|---|---|---|
| A2 + NetworkManager | ~300 MB | 无 | 可用 |
| **A2 不装 NM（推荐先做）** | **~280 MB** | 无（configd 自动降级） | 不可用，用网页/CLI 配网 |
| A2 不装 NM + 给 configd 加 `WpaNet` | ~280 MB | 1–2 天（实现 `Net` trait 的 4 个方法，走 `wpa_cli`） | 可用 |

`Net` trait 只有四个方法（`configd/src/net.rs`）：

```rust
async fn status(&self)  -> NetResult<proto::NetStatusResult>;
async fn scan(&self)    -> NetResult<proto::NetScanResult>;
async fn connect(&self, ssid: &str, psk: Option<&str>) -> NetResult<proto::ConnectResult>;
async fn forget(&self, ssid: &str) -> NetResult<proto::ForgetResult>;
```

实现 `WpaNet` 就是把这四个方法翻译成 `wpa_cli`/`iw`/`ip` 调用，体积只有几百行，
不用引入 NM 的 23.5 MB。

## 为什么值得先不装 NM

- 省 **23.5 MB**（NM 包 + libnm + ppp/team 等依赖），镜像 ~280 MB；
- 少一个会接管 `wlan0`、写 `/etc/NetworkManager/system-connections` 的守护进程，
  和我们的 AP/STA 逻辑不会打架；
- 我们已经有经过验证的配网体验（AP + captive portal + multi-profile），
  比 App 里的配网入口更“傻瓜式”。

代价是：如果产品要求“手机 App 一站式配网”，要么加 `WpaNet`，要么在 App 里改成
打开我们热点上的网页（`http://10.42.0.1`）。

## BSP 侧要做的（product profile）

1. `ROOTFS_INIT=systemd` 分支：`systemd-sysv + systemd`（含 journald），不装 NM；
2. 把现在的 rcS 钩子换成 systemd units：
   - `microduck-net.service`（auto，oneshot + RemainAfterExit）
   - `microduck-ap.service`（可选，`ap.conf` ENABLED=1）
   - `microduck-bt.service`、`sshd.service`、`avahi-daemon.service`、udev 自带
   - ZRAM/扩容：`microduck-zram.service`、`microduck-grow.service`
3. 保留 udev（systemd 环境里由 systemd-udevd 接管，规则文件不用改）；
4. 继续用 `microduck-net`/`microduck-ap` 管 wlan0，`/etc/microduck/` 配置不变。

## 待确认

- `configd` 在 `UnavailableNet` 下，BLE 配网流程是否仍能完成“配手柄”之外的动作；
- `btd`（bluez）和 `pad` 配对不依赖 NM（代码里只有 configd 用 NM，btd 用 bluer/bluez）；
- 手机 App 的“配网”入口能否改成打开 `duck-XXXX.local` 的网页。
