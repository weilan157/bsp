#!/bin/sh
# codec-early-test.sh —— 一次开机把 AIC3104 的三件事同时测出来
#
#   1) BASE：不写任何 mixer，只轮询 0x18 —— codec 会不会"自己"在~10s 死掉？
#   2) MIX ：只开 Line 通路（不碰 HP / 不碰采集），每条之后检查存活；
#   3) PLAY：立刻放 20 秒 440Hz 正弦，同时轮询存活。
#
# 为什么这么设计（2026-10-29 结论）：
#   codec 在开机约 10 秒从 I2C 上消失（地址阶段就 NACK），而同一对 PJ22/PJ23
#   上的 0x6a(IMU) 一直活着 -> 总线/+3V3 没问题；codec 独有的电源只剩
#   +1V8(DVDD, U3 XC6206)。10s 正好是 audio-init 上电输出级的时刻，所以要么
#   是我们的 mixer 把它弄死，要么是开机流程里别的东西。这个脚本一次开机
#   就能把两者分开，并且顺便验证"codec 到底能不能出声"。
#
# 装法（写进 SD 卡即生效，不用重刷镜像）：
#   wget -O /usr/local/bin/codec-early.sh \
#     https://raw.githubusercontent.com/weilan157/bsp/cubie-a7z-a733/tools/codec-early-test.sh
#   chmod +x /usr/local/bin/codec-early.sh
#   printf '%s\n' '[Unit]' 'Description=codec early test' \
#     'DefaultDependencies=no' 'After=sysinit.target' 'Before=multi-user.target' \
#     '[Service]' 'Type=simple' 'ExecStart=/usr/local/bin/codec-early.sh' \
#     '[Install]' 'WantedBy=multi-user.target' \
#     > /etc/systemd/system/codec-early.service
#   systemctl daemon-reload
#   systemctl disable microduck-audio.service alsa-restore.service
#   systemctl enable codec-early.service
#   reboot
#
# 读结果：cat /var/log/codec-early.log

LOG=/var/log/codec-early.log
exec >>"$LOG" 2>&1

u()     { cut -d' ' -f1 /proc/uptime; }
alive() { i2cget -y -f 7 0x18 0x02 >/dev/null 2>&1; }
dump()  { echo "--- dmesg ---"; dmesg | tail -15; echo "--- end ---"; }

echo "=== boot $(date -Is) kernel=$(uname -r) ==="

i=0
while [ "$i" -lt 900 ]; do
	[ -e /sys/class/i2c-adapter/i2c-7 ] && [ -e /proc/asound/card0/id ] && break
	i=$((i + 1))
	sleep 0.1
done
echo "$(u) ready card=$(cat /proc/asound/card0/id 2>/dev/null) i2c7=$([ -e /sys/class/i2c-adapter/i2c-7 ] && echo y || echo n)"

# ---------- 1) 基线：完全不写 mixer ----------
echo "--- BASE (no mixer writes, ~7s) ---"
prev=
n=0
while [ "$n" -lt 24 ]; do
	if alive; then r=OK; else r=DEAD; fi
	if [ "$r" != "$prev" ]; then
		echo "$(u) BASE $r"
		[ "$r" = DEAD ] && dump
		prev=$r
	fi
	n=$((n + 1))
	sleep 0.3
done

# ---------- 2) 只开 Line 通路 ----------
echo "--- MIX (line out only) ---"
for pair in \
	"PCM Playback Volume|127,127" \
	"Line DAC Playback Volume|118,118" \
	"Line Playback Volume|9,9" \
	"Line Playback Switch|on,on" \
	"Left Line Mixer DACL1|on" \
	"Right Line Mixer DACR1|on" \
	"Line DAC|on" \
	; do
	nm=${pair%%|*}; vv=${pair#*|}
	amixer -c 0 cset name="$nm" "$vv" >/dev/null 2>&1
	if alive; then r=OK; else r=DEAD; fi
	echo "$(u) MIX [$r] $nm=$vv"
	if [ "$r" = DEAD ]; then dump; break; fi
	sleep 0.3
done

# ---------- 3) 立刻放 20 秒正弦 ----------
echo "$(u) PLAY start"
speaker-test -D hw:0,0 -c 2 -t sine -f 440 -l 20 >/dev/null 2>&1 &
sp=$!
prev=
n=0
while [ "$n" -lt 80 ] && kill -0 "$sp" 2>/dev/null; do
	if alive; then r=OK; else r=DEAD; fi
	if [ "$r" != "$prev" ]; then
		echo "$(u) PLAY $r"
		[ "$r" = DEAD ] && dump
		prev=$r
	fi
	n=$((n + 1))
	sleep 0.3
done

if alive; then tail=alive; else tail=dead; fi
echo "$(u) PLAY end codec=$tail  (mx=$(amixer -c 0 cget name='Line Playback Switch' 2>/dev/null | grep -m1 values=))"
