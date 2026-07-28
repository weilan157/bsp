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

实时测试：`extra-packages.list` 含 `rt-tests` / `stress-ng`；板上执行 `sudo rt-latency-test`。
