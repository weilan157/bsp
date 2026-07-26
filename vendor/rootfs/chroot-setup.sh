#!/bin/bash
# 在 chroot 内执行：官方 Debian 最小系统配置（无桌面）

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export APT_INSTALL="apt-get install -y --no-install-recommends"

HOSTNAME="${ROOTFS_HOSTNAME:-rockchip}"
LOCALE="${ROOTFS_LOCALE:-en_US.UTF-8}"
ROOT_PASSWORD="${ROOTFS_ROOT_PASSWORD:-root}"
USER_NAME="${ROOTFS_USER:-debian}"
USER_PASSWORD="${ROOTFS_USER_PASSWORD:-debian}"

echo ">>> 配置 sources.list（仅 main，默认清华源）"
cat > /etc/apt/sources.list <<EOF
deb http://${DEBIAN_MIRROR}/debian ${DEBIAN_RELEASE} main
deb http://${DEBIAN_MIRROR}/debian ${DEBIAN_RELEASE}-updates main
deb http://${DEBIAN_MIRROR}/debian-security ${DEBIAN_RELEASE}-security main
EOF

echo ">>> apt update"
apt-get update

echo ">>> 安装基础包"
# shellcheck disable=SC2086
${APT_INSTALL} systemd systemd-sysv systemd-timesyncd dbus sudo openssh-server \
	locales ca-certificates net-tools iproute2 iputils-ping \
	ifupdown isc-dhcp-client wget curl nano less kmod \
	wpasupplicant iw rfkill wireless-regdb

if [[ -f /tmp/extra-packages.list ]]; then
	mapfile -t EXTRA_PKGS < <(grep -vE '^\s*(#|$)' /tmp/extra-packages.list || true)
	if [[ ${#EXTRA_PKGS[@]} -gt 0 ]]; then
		echo ">>> 安装额外包: ${EXTRA_PKGS[*]}"
		# shellcheck disable=SC2086
		${APT_INSTALL} "${EXTRA_PKGS[@]}"
	else
		echo ">>> 无额外包（extra-packages.list 仅注释/空行）"
	fi
fi

echo ">>> locale ${LOCALE}"
sed -i "s/^# *${LOCALE}/${LOCALE}/" /etc/locale.gen 2>/dev/null || \
	echo "${LOCALE} UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/default/locale

echo ">>> hostname"
echo "${HOSTNAME}" > /etc/hostname
echo "127.0.1.1 ${HOSTNAME}" >> /etc/hosts

echo ">>> 用户"
echo "root:${ROOT_PASSWORD}" | chpasswd
if ! id "${USER_NAME}" >/dev/null 2>&1; then
	useradd -m -s /bin/bash "${USER_NAME}"
	echo "${USER_NAME}:${USER_PASSWORD}" | chpasswd
	usermod -aG sudo "${USER_NAME}"
fi

echo ">>> 启用 ssh / timesyncd"
systemctl enable ssh 2>/dev/null || true
# 板子无有效 RTC 时常停在错误日期，apt/sqv 会报 Not live until
systemctl enable systemd-timesyncd.service 2>/dev/null || true

echo ">>> 启用 rockchip-partnames（原生 systemd，替代 SysV）"
chmod 755 /usr/local/sbin/rockchip-partnames 2>/dev/null || true
rm -f /etc/init.d/S02rockchip-partnames
if [[ -f /etc/systemd/system/rockchip-partnames.service ]]; then
	systemctl enable rockchip-partnames.service 2>/dev/null || true
fi

echo ">>> 启用 FIQ 调试串口 getty (ttyFIQ0)"
# kernel cmdline 的 console=ttyFIQ0 会触发生成 serial-getty@ttyFIQ0，
# 但 FIQ 口不产生 udev unit，会卡 1.5min 后失败；改用自备 unit。
systemctl mask serial-getty@ttyFIQ0.service 2>/dev/null || true
if [[ -f /etc/systemd/system/fiq-getty.service ]]; then
	systemctl enable fiq-getty.service 2>/dev/null || true
fi
# 允许 root 在调试串口登录
touch /etc/securetty
if ! grep -qx 'ttyFIQ0' /etc/securetty; then
	echo 'ttyFIQ0' >> /etc/securetty
fi

echo ">>> 清理"
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/*

echo ">>> rootfs 配置完成"
