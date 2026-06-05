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

echo ">>> 配置 sources.list（仅 main）"
cat > /etc/apt/sources.list <<EOF
deb http://${DEBIAN_MIRROR}/debian ${DEBIAN_RELEASE} main
deb http://${DEBIAN_MIRROR}/debian ${DEBIAN_RELEASE}-updates main
deb http://security.debian.org/debian-security ${DEBIAN_RELEASE}-security main
EOF

echo ">>> apt update"
apt-get update

echo ">>> 安装基础包"
# shellcheck disable=SC2086
${APT_INSTALL} systemd systemd-sysv dbus sudo openssh-server \
	locales ca-certificates net-tools iproute2 iputils-ping \
	ifupdown isc-dhcp-client wget curl nano less

if [[ -f /tmp/extra-packages.list ]]; then
	echo ">>> 安装额外包"
	xargs -a /tmp/extra-packages.list ${APT_INSTALL}
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

echo ">>> 启用 ssh"
systemctl enable ssh 2>/dev/null || true

echo ">>> 清理"
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/*

echo ">>> rootfs 配置完成"
