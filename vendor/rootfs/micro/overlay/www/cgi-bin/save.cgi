#!/bin/sh
# busybox httpd CGI：保存 WiFi 配置并切换到 STA 模式
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

urldecode() {
	printf '%s' "$1" | sed -e 's/+/ /g' -e 's/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g' | xargs -0 printf '%b' 2>/dev/null || printf '%s' "$1"
}

SSID=""
PSK=""
OLDIFS="$IFS"
IFS='&'
for kv in $QUERY_STRING; do
	case "$kv" in
		ssid=*) SSID=$(urldecode "${kv#ssid=}") ;;
		psk=*)  PSK=$(urldecode "${kv#psk=}") ;;
	esac
done
IFS="$OLDIFS"

echo "Content-Type: text/html; charset=utf-8"
echo

if [ -z "$SSID" ] || [ -z "$PSK" ]; then
	echo '<h3>参数不完整</h3><p><a href="/">返回</a></p>'
	exit 0
fi

# 写配置（update_config=0：避免 wpa_supplicant 把 hex PSK 回写覆盖）
cat > /etc/wpa_supplicant/wpa_supplicant.conf <<EOF
ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev
update_config=0
country=CN
ap_scan=1
disable_scan_offload=1
p2p_disabled=1

network={
	ssid="${SSID}"
	psk="${PSK}"
	key_mgmt=WPA-PSK
	scan_ssid=1
}
EOF

echo "<h3>已保存：${SSID}</h3>"
echo "<p>正在关闭热点并连接，请稍候……</p>"
echo "<p>如果 30 秒后仍未联网，热点 <b>microduck-setup</b> 会重新出现。</p>"

# 异步切换：先回页面，再关 AP、起 STA
(
	sleep 2
	pkill -x dnsmasq 2>/dev/null
	pkill -x hostapd 2>/dev/null
	pkill -f 'busybox httpd' 2>/dev/null
	pkill -f microduck-wifi 2>/dev/null
	ip addr flush dev wlan0 2>/dev/null
	ip link set wlan0 down 2>/dev/null
	iw dev wlan0 set type managed 2>/dev/null
	ip link set wlan0 up 2>/dev/null
	/usr/sbin/microduck-wifi >/dev/null 2>&1 &
) >/dev/null 2>&1 &
