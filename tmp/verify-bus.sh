#!/bin/bash
cd /root/bsp733/out/a733 || exit 1
dd if=a733-micro.img of=/tmp/bus.ext4 bs=1M skip=32 status=none
echo ===INFO===
debugfs -R 'cat /etc/microduck/build-info' /tmp/bus.ext4 2>/dev/null | head -4
echo ===AUDIO-LINK===
debugfs -R 'ls -l /etc/systemd/system/multi-user.target.wants' /tmp/bus.ext4 2>/dev/null | grep -i audio
echo ===DTB===
debugfs -R 'dump /boot/sun60i-a733-cubie-a7z.dtb /tmp/bus.dtb' /tmp/bus.ext4 2>/dev/null
dtc -I dtb -O dts /tmp/bus.dtb 2>/dev/null | grep -A4 'tlv320aic3104@18' | head -6
echo ===MACH===
dtc -I dtb -O dts /tmp/bus.dtb 2>/dev/null | grep -A8 'i2s0_mach {' | grep status
echo ===IMG-RETRY===
debugfs -R 'dump /boot/Image /tmp/bus.Image' /tmp/bus.ext4 2>/dev/null
strings /tmp/bus.Image | grep -c 'bus recovery + retry'
