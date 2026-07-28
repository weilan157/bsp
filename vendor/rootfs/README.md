# Debian rootfs（riscv64）

官方 debootstrap **minbase**，架构由 `config.env` 的 `DEBIAN_ARCH=riscv64` 决定。

| 项 | 默认 |
|----|------|
| 发行版 | `trixie` |
| 架构 | `riscv64` |
| 主机名 | `orangepi` |
| 用户 | `weiqi` / `321` |

Ky 固件 `esos.elf` 安装到 `/lib/firmware/`。
