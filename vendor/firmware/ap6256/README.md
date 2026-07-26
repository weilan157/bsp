# AP6256 WiFi/BT 固件

泰山派默认 WiFi 模组 **AP6256**（BCM43456），内核使用 Rockchip `bcmdhd`（非主线 `brcmfmac`）。

需要文件：

| 文件 | 用途 |
|------|------|
| `fw_bcm43456c5_ag.bin` | WiFi firmware |
| `nvram_ap6256.txt` | WiFi NVRAM |
| `BCM4345C5.hcd` | 蓝牙 firmware（可选） |

`./bsp rootfs` 会自动下载（若缺失）并安装到：

- `/vendor/etc/firmware/` — 匹配当前内核默认 `CONFIG_BCMDHD_*_PATH`
- `/lib/firmware/` — Debian 惯例路径

手动下载（Armbian firmware）：

```bash
cd vendor/firmware/ap6256
curl -fLO https://raw.githubusercontent.com/armbian/firmware/master/fw_bcm43456c5_ag.bin
curl -fLO https://raw.githubusercontent.com/armbian/firmware/master/nvram_ap6256.txt
curl -fLO https://raw.githubusercontent.com/armbian/firmware/master/BCM4345C5.hcd
```

板上验证：

```bash
# 1) 固件
ls /vendor/etc/firmware/fw_bcm43456c5_ag.bin /lib/firmware/fw_bcm43456c5_ag.bin

# 2) 驱动（当前 defconfig 默认编成 ko，需加载）
ls /sys/bus/sdio/devices/
modprobe bcmdhd
dmesg | grep -iE 'mmc2|sdio|bcmdhd|dhd|wlan|pwrseq|rfkill'
ip link show wlan0
```

若 `modprobe` 后仍无 `wlan0`，看 SDIO 是否枚举到卡（`/sys/bus/sdio/devices/` 为空则是供电/32K 时钟/管脚问题）。

若 `ifup wlan0` 出现 `HT Avail timeout` / `failed to power up wifi chip`：
固件已能下载，但是模组 32K 时钟未开。设备树需让 `sdio_pwrseq` 带 `clocks = <&hym8563>; clock-names = "ext_clock"`，
并保证 RTC `hym8563` 正常（`dmesg | grep -i hym8563`）。
