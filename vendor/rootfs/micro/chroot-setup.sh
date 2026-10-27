#!/bin/bash
# microduck 精简 rootfs：Debian 基础 + sysvinit + busybox，去掉 systemd
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
APT="apt-get install -y --no-install-recommends"

# chroot 里没有运行中的 init：让 invoke-rc.d 直接返回 101（不启动/不停止服务）。
# 不加的话每个包安装都会走一遍 "invoke-rc.d: could not determine current runlevel"，
# 在 qemu 用户态模拟下非常慢，甚至会卡住（本次构建就卡在 bluez 的配置阶段）。
cat > /usr/sbin/policy-rc.d <<'EOF'
#!/bin/sh
exit 101
EOF
chmod 755 /usr/sbin/policy-rc.d

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
	i2c-tools \
	gdisk \
	openssh-server dbus avahi-daemon libnss-mdns \
	iptables \
	iproute2 procps

INIT="${ROOTFS_INIT:-sysvinit}"
if [ "$INIT" = "systemd" ]; then
	echo ">>> systemd（product profile，不装 NetworkManager）"
	${APT} systemd-sysv systemd
else
	echo ">>> 用 sysvinit 取代 systemd"
	${APT} sysvinit-core
	# 只卸 systemd 本体；udev 保留（bluez 依赖它）
	apt-get purge -y systemd-sysv systemd 2>/dev/null || true
	apt-get autoremove -y --purge 2>/dev/null || true
fi

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

echo ">>> SSH / mDNS"
# 现场排查优先：允许 root 密码登录（产品镜像请改 sshd_config / 用密钥）。
# 用 sshd_config.d 的 drop-in，而不是改 sshd_config 本体 —— 两者都是
# conffile，但 drop-in 是我们新建的文件，不参与 dpkg 的 conffile 冲突检查。
mkdir -p /run/sshd /run/dbus /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/10-microduck.conf <<'EOF'
PermitRootLogin yes
PasswordAuthentication yes
KbdInteractiveAuthentication yes
PermitEmptyPasswords no
UseDNS no
EOF
# 主机密钥不在镜像里生成（否则所有板子共用同一份 key），
# 由首次启动的 /usr/sbin/microduck-sshd 执行 ssh-keygen -A 补齐。

if [ "$INIT" = "systemd" ]; then
	echo ">>> 启用 systemd 服务（不含 NetworkManager）"
	enable_unit() {
		unit="$1"; target="$2"
		systemctl enable "$unit" >/dev/null 2>&1 && return 0
		link="$(readlink -f "/lib/systemd/system/$unit" 2>/dev/null || true)"
		[ -n "$link" ] || link="/usr/lib/systemd/system/$unit"
		mkdir -p "/etc/systemd/system/${target}.wants"
		ln -sf "$link" "/etc/systemd/system/${target}.wants/$unit"
	}
	# 注意：不要同时启用 microduck-net（平台版）和 microduck-wifi（带 AP 配网
	# 回退 + AP/STA 共存）—— 两者都会去管 wlan0，会互相抢。
	# microduck-ap 也不要开机自启：它要在 STA 关联成功之后才由 wifi 服务拉起。
	for u in ssh.service avahi-daemon.service bluetooth.service \
		microduck-wifi.service microduck-sshd.service microduck-bt.service \
		microduck-audio.service; do
		enable_unit "$u" multi-user.target
	done
	for u in microduck-grow.service microduck-zram.service; do
		enable_unit "$u" sysinit.target
	done
	enable_unit getty@tty1.service getty.target
	# 屏蔽平台版 net/ap：WiFi 与 AP 统一由 microduck-wifi.service 负责，
	# 否则两个服务会同时配置 wlan0。
	systemctl mask microduck-net.service microduck-ap.service >/dev/null 2>&1 || true
	# Debian 装 hostapd/dnsmasq/wpasupplicant 时会给它们 enable 开机自启，
	# 这跟我们的 microduck-wifi / microduck-ap 会抢 wlan0（两套 hostapd、两个
	# wpa_supplicant）。统一屏蔽，全部由 microduck-wifi 在运行时按需拉起。
	systemctl mask hostapd.service dnsmasq.service wpa_supplicant.service \
		>/dev/null 2>&1 || true
	systemctl disable hostapd.service dnsmasq.service wpa_supplicant.service \
		>/dev/null 2>&1 || true
fi
# avahi 只广播主机名；不装一堆 service 文件
sed -i 's/^#*hosts:.*/hosts: files mdns4_minimal [NOTFOUND=return] dns mdns4/' /etc/nsswitch.conf 2>/dev/null || true

echo ">>> 精简"
if [ "${ROOTFS_TINY:-n}" = y ]; then
	echo ">>> 极致精简（去掉 apt/hwdb/perl 运行时）"
	# apt 在 Debian 里是 Essential，必须带 --allow-remove-essential；sqv 是它的依赖
	apt-get purge -y --allow-remove-essential apt >/dev/null 2>&1 || true
	apt-get purge -y sqv >/dev/null 2>&1 || true
	# udev 的硬件数据库对这块板子没用（12.9 MB 的 hwdb.bin + 7 MB 源文件）
	rm -rf /usr/lib/udev/hwdb.d /usr/lib/udev/hwdb.bin
	# perl 运行时（dpkg 本体是 C，不需要 perl；adduser 也不用）
	rm -rf /usr/lib/aarch64-linux-gnu/perl* /usr/lib/arm-linux-gnueabihf/perl* \
		/usr/share/perl* /usr/bin/perl* /usr/lib/*/perl-base 2>/dev/null || true
fi
apt-get clean || true
rm -rf /var/lib/apt/lists/* /var/cache/apt/* \
	/usr/share/doc/* /usr/share/man/* /usr/share/info/* \
	/usr/share/locale/* /usr/share/bash-completion \
	/var/lib/systemd /run/systemd 2>/dev/null || true

echo ">>> 启动脚本"
# inittab / rcS / fstab 由 overlay 提供，构建脚本最后会再覆盖一次
chmod 755 /etc/init.d/rcS /usr/sbin/microduck-* 2>/dev/null || true

echo ">>> 完成 (rootfs 内容 $(du -sm --exclude=/proc / 2>/dev/null | cut -f1) MB)"
