#!/bin/bash
# 在 chroot 内执行：官方 Debian 最小系统配置（无桌面）

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export APT_INSTALL="apt-get install -y --no-install-recommends"

HOSTNAME="${ROOTFS_HOSTNAME:-orangepi}"
LOCALE="${ROOTFS_LOCALE:-en_US.UTF-8}"
ROOT_PASSWORD="${ROOTFS_ROOT_PASSWORD:-root}"
USER_NAME="${ROOTFS_USER:-weiqi}"
USER_PASSWORD="${ROOTFS_USER_PASSWORD:-321}"

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
	ifupdown isc-dhcp-client wget curl nano less kmod

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
systemctl enable systemd-timesyncd.service 2>/dev/null || true

echo ">>> 串口登录（overlay 已 mask serial-getty@ttyS0、启用 console-getty）"
# Ky UART 作 console 时 udev 常不产生 dev-ttyS0.device；见 vendor/rootfs/overlay/.../systemd
systemctl set-default multi-user.target 2>/dev/null || true
touch /etc/securetty
grep -qxF 'ttyS0' /etc/securetty || echo 'ttyS0' >> /etc/securetty
grep -qxF 'console' /etc/securetty || echo 'console' >> /etc/securetty

# 允许 root SSH 登录（调试用）
if [[ -f /etc/ssh/sshd_config ]]; then
	sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
fi

echo ">>> chroot 配置完成"
