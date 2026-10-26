# 镜像瘦身：400 MB → 271 MB

实测环境：本机 WSL2 + 交叉编译（`./bsp rootfs --clean && ./bsp pack`），
A733 分支、`ROOTFS_TINY=y`（默认）、`MICRODUCK_MIN_MODULES=y`（默认）。

## 前后对比

| 项 | 优化前 | 优化后 | 省 |
|---|---|---|---|
| rootfs 目录 | 261 MB | 215 MB | −46 MB |
| rootfs.ext4 | 368 MB（空闲 100 MB + 保留 18 MB） | 239 MB（+16 MB 余量） | −129 MB |
| **SD 镜像** | **400 MB** | **271 MB** | **−129 MB（32%）** |
| 内核模块 | 929 个 / 36 MB | 740 个 / 25 MB | −11 MB |

## 做了什么

### 1. 打包不再“估大”（最大的一刀，约 −110 MB）

`cmd_a733_pack` 原来的尺寸是 `内容 + 文件数×4KB + 64MB`，再 `×110%`，
400 MB 的 ext4 里有一半是空的。现在：

- 余量从 +64 MB 降到 +24 MB、放大系数 110% → 104%；
- `mkfs.ext4 -m 0`：不留 5% 的 root 保留块（约 −18 MB）；
- mkfs 之后 `e2fsck -fy` + **`resize2fs -M`** 把文件系统缩到实际内容，再补 16 MB 余量，
  镜像长度按真实文件大小算（分区 p2 自动跟着变短）。

### 2. `ROOTFS_TINY=y`（a733 默认，约 −40 MB）

在 chroot 里：

- `apt-get purge --allow-remove-essential apt`（+ `sqv`）——现场不需要装包；
- 删 `/usr/lib/udev/hwdb.d` 和 `hwdb.bin`（12.9 MB 编译产物 + 7 MB 源数据）；
- 删 perl 运行时（`/usr/bin/perl*`、`/usr/share/perl*`、`/usr/lib/*/perl*`）。

保留：`sshd`、`ssh-keygen`、`hostapd`、`dnsmasq`、`dbus/avahi`、`bluez`、`wpa_supplicant`。

### 3. 模块裁剪（`MICRODUCK_MIN_MODULES=y`，约 −11 MB）

`rootfs_install_platform_modules` 在 `modules_install` 之后删掉其它平台的驱动
（qcom / renesas / rockchip / mediatek / tegra / ath / marvell / brcm / broadcom /
samsung / fsl / imx / wcn / ti / amlogic / nvidia / intel / amd / xilinx），然后重新
`depmod`。A733 相关的 aic8800、蓝牙、HID、IMX219/OV5695、TLV320 都保留。

## 还能再小的地方（按性价比）

| 项 | 预计 | 风险/代价 |
|---|---|---|
| `coreutils` → busybox 软链 | −18 MB | 低风险但脚本兼容性要过一遍（`install -m`、`stat` 等） |
| 内核 Image 换 gzip FIT | −27 MB | 需要 u-boot 打开 FIT/GZIP 并改成 `bootm`；defconfig 里没有现成的 FIT，**未做** |
| 删 `dpkg` + `/var/lib/dpkg` | −13 MB | 删了就没法再用 dpkg 查/装包 |
| `config` 分区 16 MiB → 4 MiB | −12 MB | 偏离 rsdk 官方布局 |
| util-linux 只留 `mount/blkid/fdisk` | −4 MB | 要逐个裁 |
| ext4 余量 16 MB → 8 MB | −8 MB | 首次启动日志空间更紧 |

再往下（libc 23 MB、libssl 7.8 MB、bluez 5.4 MB、wpa 3.8 MB）都是实际要用的，
不建议动。

## 复现

```bash
./bsp config PLATFORM=a733
./bsp rootfs --clean      # ROOTFS_TINY=y、模块裁剪都会打印出来
./bsp pack                # 日志里会有 "rootfs.ext4 收缩到 xxx MiB"
ls -lh out/a733/a733-micro.img
```

关掉瘦身（调试用）：

```bash
ROOTFS_TINY=n MICRODUCK_MIN_MODULES=n ./bsp rootfs --clean
```

注意：`ROOTFS_TINY=y` 之后镜像里没有 `apt`，现场如果要用 `apt` 装包，得先做一版
非 tiny 的镜像，或者把包装进 overlay。
