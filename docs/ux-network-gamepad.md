# 配网 / SSH / 手柄：现状与“傻瓜式”改进方案

面向产品（Microduck 复刻机）的用户体验评审。现状依据
[`fanhao375/microduck-replica`](https://github.com/fanhao375/microduck-replica)：
`software/image/overlay/usr/local/sbin/microduck-netcheck`、
`microduck-firstboot`、`gamesir-xboxd` 的 udev 规则与 systemd 单元，以及 README 的
“烧录 → 热点配网 → 标定 → 配手柄 → 站立行走”。

## 1. 现在的逻辑

### 配网（netcheck）

- 设备用 **NetworkManager** 管 `wlan0`，`microduck-netcheck` 轮询 `nmcli`：
  - 有已保存 WiFi：断开后等 **45 s** 才开热点；
  - 没有任何已保存 WiFi（新卡）：断开那一拍就开热点（实测第一次开机约 **2 分钟**才看到热点）；
  - `connecting` 状态最多等 **120 s**，之后按失败处理再等 45 s；
  - 热点 `Microduck-Hotspot` / PSK `microduck` / `10.42.0.1`，连续 5 分钟无客户端才回去试 WiFi；
  - 状态写到 `/run/microduck/net.json`，Studio 读它显示。
- 配网动作在 **Microduck Studio**（网页中控）里完成：连热点 → 打开 Studio → 选 SSID/输密码。

### SSH

- 镜像里启用了 `ssh.service`（有 `ssh.service.d` 覆盖），`avahi`/mDNS 的配置也在
  （`90-microduck-mdns.conf`、`resolved.conf.d`），所以理论上 `duck-xxxx.local` 可用。

### 手柄

- udev 规则：`SUBSYSTEM=="usb"` 且 VID 匹配 → `SYSTEMD_WANTS=gamesir-xboxd.service`；
- 服务 `gamesir-xboxd` 把 Xbox/GameSir 手柄桥接给 robotd；
- 没有蓝牙手柄的配对/回连逻辑，也没有“手柄连上 → 进入可操控状态”的明确反馈。

## 2. 用户会卡在哪

| 场景 | 现在的体验 | 问题 |
|---|---|---|
| 新机第一次配网 | 等 1–2 分钟热点出现，还要知道去连 `Microduck-Hotspot`、开 Studio | 不知道要等；SSID/密码全设备一样，多台同场会连错 |
| 换网 | 先让设备断网 → 等 45 s 热点 → 连热点 → Studio 改 | 一旦改错密码就失联，只能等热点 |
| 手机连上热点后 | 没有自动弹窗，要手动输 `10.42.0.1` 或开 App | 不是“傻瓜式” |
| SSH 排查 | 要自己找 IP；`.local` 依赖 avahi 正常 | 现场没显示器，找不到 IP 就抓瞎 |
| 插手柄 | USB 匹配才起桥；蓝牙手柄要手动配对 | 插上不知道有没有生效；断开后没有急停提示 |

## 3. 目标体验（越少折腾越好）

### 3.1 首次开机：0 操作

1. 上电 **3 s 内**起热点：SSID = `duck-XXXX`（每台唯一），PSK = 8 位随机，
   贴在机身/包装上，同时印二维码 `WIFI:T:WPA;S:duck-XXXX;P:********;;`。
2. 手机连上后 **自动弹 captive portal**（dnsmasq 把 `/#/` 指到 `10.42.0.1`，
   页面直接用 Studio 的配网页或一个极简表单）：列出周边 SSID → 选 → 输密码 → 保存。
3. 设备后台连 STA（AP 保持 30 s 作为回退），页面轮询 `/run/microduck/net.json`
   显示“已连上 / 密码错 / 找不到 SSID”，并给出 `duck-XXXX.local` 和 IP。
4. 连上后 AP 自动关闭；STA 失败则 AP 保留，用户可以直接重试。

关键改动：**AP 先起、STA 后台连**（不再等 45 s），**每台独立 SSID/PSK**，
**captive portal**（不再依赖用户知道 IP/App）。

### 3.2 换网：1 步

- 已联网时浏览器打开 `http://duck-XXXX.local` → 同一个配网页 → 选新 SSID → 保存；
  设备切网，页面显示结果；失败自动回到原网络或 AP。
- 没有手机/电脑时：长按机身按键 3 s 强制进配网模式（AP 重启，STA 暂停）。
- 已保存多个 WiFi 时按优先级自动连（家里/工作室/手机热点），不用每次重配。

### 3.3 SSH 排查：0 配置

- `sshd` 默认开，首启生成 host key；`ssh microduck@duck-XXXX.local`（mDNS），
  密码 = PSK 或贴在机身上的随机密码。
- `microduck ip` 打印所有地址（wlan0/usb0/AP）、`microduck status` 打印网络状态 +
  `/run/microduck/net.json` + 最近日志；`microduck logs` 导出诊断包。
- 兜底：USB-C 插入电脑出现 RNDIS 网卡（`10.55.0.1`）+ 可选 ACM 串口，
  不依赖 WiFi 也能 SSH。
- 串口 console 只留调试用（UART0 已让给舵机，可用 USB gadget 串口）。

### 3.4 手柄：插上即用、拔下即停

- udev 匹配 **VID 列表**（Xbox/GameSir/DualShock/DualSense/8BitDo…）和
  `KERNEL=="js[0-9]*"`，不依赖单一 VID；插上即启动 `robotd`/桥接服务。
- 进入“可操控”时给反馈：蜂鸣一声 / 板载 LED 变色（有硬件就做，没有就 Studio 弹提示）。
- 蓝牙手柄：首次配对后 `trust` + 保存 link key，之后开机自动回连；
  手柄没连上时 Studio 显示“等待手柄”，不误导用户。
- **安全**：手柄断开 > 5 s 自动急停（电机卸力），状态回 idle；重新连上再进入 ready。
- 多手柄先到先得，后到的忽略并在 Studio 提示。

## 4. 落地拆解

### 产品层（复刻镜像，systemd + NetworkManager）

| 改动 | 位置 | 收益 |
|---|---|---|
| AP 先起（hostapd 随 boot 启动），STA 后台连 | `microduck-netcheck` + 新的 `microduck-ap.service` | 首次配网从 1–2 分钟降到 <10 s |
| 每台独立 SSID/PSK + 二维码 | `microduck-firstboot` 生成 hostapd/二维码 | 多台同场不串、密码不公开 |
| captive portal | dnsmasq `address=/#/10.42.0.1` + Studio 静态页（或极简表单） | 连上就弹窗，不用记 IP |
| 多 WiFi 配置 + 优先级 + 失败回退 | NM 多 profile（`autoconnect-priority`） | 换网不用重配 |
| 修改配网页常驻 | Studio 加 `/setup` 路由，STA 下也可访问 | 换网不用回热点 |
| mDNS + SSH 默认开 | 确认 `avahi-daemon`/`sshd` 起，`duck-xxxx.local` | 不用找 IP |
| 诊断命令/页面 | `microduck ip/status/logs`，Studio 导出诊断 | 现场排查快 |
| 蓝牙手柄配对/回连/急停 | robotd + bluez（trust、link key、超时卸力） | 插上/开机就好 |

### BSP 层（本仓库的 micro rootfs，sysvinit）

在 `vendor/a733/overlay` 里给了最小可用的一套（见下）：
`microduck-net`（wpa_supplicant 多 profile：`scan/add/list/switch/forget/status/auto`）、
`microduck-ip`、`microduck-pad`（udev 触发，起 robotd/写状态）、`90-microduck-pad.rules`，
rcS 里启动 `udevd`、`sshd`、`avahi`、`microduck-net auto`。
AP 兜底（hostapd+dnsmasq+portal）属于产品层，BSP 里只留了文档和接口。

## 5. 优先级

1. **P0**：AP 先起 + 每台独立 SSID/PSK + captive portal（首次体验 + 多机冲突）
2. **P0**：换网页面常驻（`duck-xxxx.local/setup`）+ 多 profile 自动连
3. **P1**：SSH/mDNS 默认可用 + `microduck ip/status/logs`
4. **P1**：手柄 udev VID 列表 + 连接/断开反馈 + 断开急停
5. **P2**：蓝牙手柄自动回连；USB-C RNDIS/ACM 兜底
6. **P2**：长按按键进配网、状态 LED
