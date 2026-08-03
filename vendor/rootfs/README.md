# Debian rootfs（riscv64）

官方 debootstrap **minbase**，架构由 `config.env` 的 `DEBIAN_ARCH=riscv64` 决定。

| 项 | 默认 |
|----|------|
| 发行版 | `trixie` |
| 架构 | `riscv64` |
| 主机名 | `orangepi` |
| 用户 | `weiqi` / `321` |

Ky 固件 `esos.elf` 安装到 `/lib/firmware/`。

串口登录：overlay 中 mask `serial-getty@ttyS0`、启用 `console-getty`（避免等 `dev-ttyS0.device`）。

Shell：`/etc/profile.d/bsp-path.sh` 为普通用户补上 `/sbin`、`/usr/sbin`（可直接 `ifconfig`）；工具链到 `/usr/local/bin`。

实时测试：`extra-packages.list` 含 `rt-tests` / `stress-ng`；板上执行 `sudo rt-latency-test`。

IgH EtherCAT（默认 `KERNEL_ETHERCAT=y`，外置官方模块）：

- `etc/network/interfaces`：`eth0`/`eth1`（YT8531C）DHCP；PCIe `enp*` 为 EtherCAT（manual）
- `etc/ethercat.conf` + `ethercat.service`：`ethercat-board-conf` 解析双 RTL8125 → `ethercatctl start`
- `etc/udev/rules.d/99-ethercat.rules`：`/dev/EtherCAT*` 权限
- 构建时安装 `ec_*.ko`、`ethercat` CLI、`libethercat`、`ecrt.h`
- `usr/local/sbin/ethercat-info` / `ethercat-slaves`：自检与备用扫站（优先用官方 `ethercat slaves`）
