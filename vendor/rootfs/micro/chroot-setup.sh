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
	iproute2 procps \
	openssh-server dbus avahi-daemon libnss-mdns \
	hostapd dnsmasq

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

echo ">>> hostname / 用户"
echo "${HOSTNAME}" > /etc/hostname
touch /etc/hosts
grep -q "^127.0.1.1" /etc/hosts || echo "127.0.1.1 ${HOSTNAME}" >> /etc/hosts
echo "root:${ROOT_PASSWORD}" | chpasswd

echo ">>> SSH / mDNS"
# 现场排查优先：允许 root 密码登录（产品镜像请改 sshd_config / 用密钥）
mkdir -p /run/sshd /run/dbus
cat > /etc/ssh/sshd_config.d/10-microduck.conf <<'EOF'
PermitRootLogin yes
PasswordAuthentication yes
UseDNS no
EOF
ssh-keygen -A >/dev/null 2>&1 || true

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
	for u in ssh.service avahi-daemon.service bluetooth.service \
		microduck-net.service microduck-bt.service microduck-ap.service; do
		enable_unit "$u" multi-user.target
	done
	for u in microduck-grow.service microduck-zram.service; do
		enable_unit "$u" sysinit.target
	done
	enable_unit getty@tty1.service getty.target
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
