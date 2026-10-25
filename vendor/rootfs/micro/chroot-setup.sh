#!/bin/bash
# microduck 精简 rootfs：Debian 基础 + sysvinit + busybox，去掉 systemd
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
APT="apt-get install -y --no-install-recommends"

HOSTNAME="${ROOTFS_HOSTNAME:-microduck}"
ROOT_PASSWORD="${ROOTFS_ROOT_PASSWORD:-root}"

echo ">>> sources.list"
cat > /etc/apt/sources.list <<EOF
deb http://${DEBIAN_MIRROR}/debian ${DEBIAN_RELEASE} main
deb http://${DEBIAN_MIRROR}/debian ${DEBIAN_RELEASE}-updates main
deb http://${DEBIAN_MIRROR}/debian-security ${DEBIAN_RELEASE}-security main
EOF

apt-get update

echo ">>> 安装最小运行时"
${APT} busybox-static kmod e2fsprogs util-linux \
	wpasupplicant iw rfkill bluez \
	hostapd dnsmasq \
	v4l-utils \
	fdisk \
	parted \
	alsa-utils \
	iproute2 procps

echo ">>> 用 sysvinit 取代 systemd"
${APT} sysvinit-core
# 只卸 systemd 本体；udev 保留（bluez 依赖它，且不启动它就不占启动时间）
apt-get purge -y systemd-sysv systemd 2>/dev/null || true
apt-get autoremove -y --purge 2>/dev/null || true

# 蓝牙策略：已配对设备（手柄/键鼠/耳机）开机自动重连。
# 注意不能把这个文件放进 overlay —— 它是 bluez 的 conffile，overlay 里的版本
# 会让 dpkg 在安装时弹 "Configuration file ... main.conf" 交互提示，
# 非交互环境读到 EOF 后 bluez 直接配置失败（rootfs 构建 rc=100）。
echo ">>> 蓝牙自动重连策略"
BTCFG=/etc/bluetooth/main.conf
if [ -f "${BTCFG}" ]; then
	set_bt_opt() {
		local key="$1" val="$2"
		if grep -qE "^#?[[:space:]]*${key}[[:space:]]*=" "${BTCFG}"; then
			sed -i -E "s|^#?[[:space:]]*${key}[[:space:]]*=.*|${key} = ${val}|" "${BTCFG}"
		else
			printf '%s = %s\n' "${key}" "${val}" >> "${BTCFG}"
		fi
	}
	set_bt_opt MultiProfile multiple
	set_bt_opt AutoEnable true
	set_bt_opt ReconnectAttempts 7
	set_bt_opt ReconnectIntervals 1,2,4,8,16,32,64
fi

echo ">>> hostname / 用户"
echo "${HOSTNAME}" > /etc/hostname
touch /etc/hosts
grep -q "^127.0.1.1" /etc/hosts || echo "127.0.1.1 ${HOSTNAME}" >> /etc/hosts
echo "root:${ROOT_PASSWORD}" | chpasswd

echo ">>> 精简"
apt-get clean || true
rm -rf /var/lib/apt/lists/* /var/cache/apt/* \
	/usr/share/doc/* /usr/share/man/* /usr/share/info/* \
	/usr/share/locale/* /usr/share/bash-completion \
	/var/lib/systemd /run/systemd 2>/dev/null || true

echo ">>> 启动脚本"
# inittab / rcS / fstab 由 overlay 提供，构建脚本最后会再覆盖一次
chmod 755 /etc/init.d/rcS /usr/sbin/microduck-* 2>/dev/null || true

echo ">>> 完成 (rootfs 内容 $(du -sm --exclude=/proc / 2>/dev/null | cut -f1) MB)"
