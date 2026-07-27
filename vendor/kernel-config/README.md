# Ky X1 内核配置

默认使用 `linux-ky-current.config`（来自 [orangepi-build](https://github.com/orangepi-xunlong/orangepi-build/tree/next/external/config/kernel)）。

`./bsp kernel` 会将其复制为 `.config` 并执行 `make olddefconfig`。

也可改用内核树内 defconfig：

```bash
./bsp config KERNEL_DEFCONFIG=x1_defconfig
./bsp config KERNEL_DOTCONFIG=
```
