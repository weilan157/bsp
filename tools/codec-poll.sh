#!/bin/sh
# codec-poll.sh —— 抓 TLV320AIC3104 在开机第几秒从 I2C 上掉线
#
# 背景（2026-10-29 真机结论）：
#   codec 在开机约 10 秒时不再应答 0x18（地址阶段就 NACK，状态 0x20），
#   而同一对 PJ22/PJ23 上的 0x6a（LSM6DSV16X）一直正常 —— 所以不是总线问题，
#   是 codec 自己掉电/复位。这个脚本用来把"掉线时刻"和"掉线瞬间的内核日志"
#   一起记下来，再据此判断是 mixer 初始化上电导致供电塌陷，还是 regulator 被关。
#
# 装法（写进 SD 卡的 rootfs 即生效，不需要重刷镜像）：
#
#   cp codec-poll.sh /usr/local/bin/codec-poll.sh
#   chmod +x /usr/local/bin/codec-poll.sh
#   cat >/etc/systemd/system/codec-poll.service <<'EOF'
#   [Unit]
#   Description=TLV320AIC3104 I2C liveness poll
#   DefaultDependencies=no
#   After=sysinit.target
#   Before=multi-user.target
#   [Service]
#   Type=simple
#   ExecStart=/usr/local/bin/codec-poll.sh
#   [Install]
#   WantedBy=multi-user.target
#   EOF
#   systemctl daemon-reload && systemctl enable codec-poll.service
#   reboot
#
# 读结果：
#   cat /var/log/codec-poll.log
#   期望看到类似：
#     2.10 WAIT          # i2c-7 还没注册好
#     3.42 OK            # codec 活了
#    10.36 DEAD          # 掉线时刻（关键）
#    --- dmesg ---       # 掉线瞬间的内核消息
#
# A/B 分流：`systemctl disable microduck-audio.service alsa-restore.service`
# 后重启，若一直 OK，说明是 mixer 初始化把它弄掉的，再逐条 amixer 二分。

LOG=/var/log/codec-poll.log
exec >>"$LOG" 2>&1

echo "=== boot $(date -Is) kernel=$(uname -r) ==="

prev=INIT
while :; do
	u=$(cut -d' ' -f1 /proc/uptime)

	if [ ! -e /sys/class/i2c-adapter/i2c-7 ]; then
		r=WAIT
	elif i2cget -y -f 7 0x18 0x02 >/dev/null 2>&1; then
		r=OK
	else
		r=DEAD
	fi

	if [ "$r" != "$prev" ]; then
		echo "$u $r"
		if [ "$r" = DEAD ]; then
			echo "--- dmesg at death ---"
			dmesg | tail -15
			echo "--- end ---"
		fi
		prev=$r
	fi

	sleep 0.3
done
