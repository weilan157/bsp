#!/bin/sh
# A733 平台钩子：udev → SSH/mDNS → WiFi 自动连接 → 手柄热插拔
# 由 micro rootfs 的 /etc/init.d/rcS 在启动末尾调用（后台，不阻塞登录）。

# 1) udev：wlan0/手柄等热插拔事件（bluez 也依赖它）
if [ -x /sbin/udevd ] || [ -x /usr/sbin/udevd ]; then
	UDEVD=/sbin/udevd
	[ -x "$UDEVD" ] || UDEVD=/usr/sbin/udevd
	mkdir -p /run/udev
	"$UDEVD" --daemon 2>/dev/null
	udevadm trigger --action=add >/dev/null 2>&1
	udevadm settle --timeout=5 >/dev/null 2>&1
fi

# 2) dbus + avahi（mDNS：duck-xxxx.local）
if [ -x /usr/bin/dbus-daemon ] && [ ! -S /run/dbus/system_bus_socket ]; then
	mkdir -p /run/dbus
	dbus-daemon --system --fork 2>/dev/null
fi
if [ -x /usr/sbin/avahi-daemon ]; then
	avahi-daemon -D 2>/dev/null
fi

# 3) SSH：host key 首次启动生成
if [ -x /usr/sbin/sshd ]; then
	[ -f /etc/ssh/ssh_host_ed25519_key ] || ssh-keygen -A >/dev/null 2>&1
	mkdir -p /run/sshd
	/usr/sbin/sshd -f /etc/ssh/sshd_config 2>/dev/null
fi

# 4) WiFi 自动连接（多 profile，见 microduck-net）
# 注：WiFi 由 rootfs 的 /usr/sbin/microduck-wifi 负责（它带 AP 配网回退：
# 没有配置或 STA 连不上时就起热点 + 网页配网）。这里不要再跑
# microduck-net auto，两者会抢 wlan0。
# if [ -x /usr/sbin/microduck-net ]; then
# 	/usr/sbin/microduck-net auto >/dev/null 2>&1 &
# fi

# 5) 已经插着的手柄（udev 只处理之后的事件）
for js in /dev/input/js*; do
	[ -e "$js" ] || continue
	/usr/sbin/microduck-pad add "$(basename "$js")" 2>/dev/null
	break
done

# 6) 蓝牙：bluetoothd 常驻 + 自动配对/回连 Xbox 手柄
[ -x /usr/sbin/microduck-bt ] && /usr/sbin/microduck-bt >/dev/null 2>&1 &

# 7) AP + STA 共存（/etc/microduck/ap.conf 里 ENABLED=1 时）
if grep -q '^ENABLED=1' /etc/microduck/ap.conf 2>/dev/null; then
	/usr/sbin/microduck-ap start >/dev/null 2>&1 &
fi

# 8) 校时（板子没有 RTC 电池；无网络时是空操作）
[ -x /usr/sbin/microduck-timesync ] && /usr/sbin/microduck-timesync >/dev/null 2>&1 &
