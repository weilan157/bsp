# Ky X1 内核配置

基线：`linux-ky-current.config`（orangepi-build 官方全量）。

`./bsp kernel`：复制基线 → 合并 `KERNEL_EXTRA_FRAGMENTS` → `make olddefconfig`。

## 默认 fragment

| 文件 | 作用 |
|------|------|
| `slim.config` | R2S 裁剪显示/无线/音频等 |
| `rt.config` | `PREEMPT_RT` + `HZ=1000`（需 `KERNEL_RT=y` 且已打补丁） |

## PREEMPT_RT

默认 `KERNEL_RT=y`：`./bsp setup kernel` / `./bsp kernel` 会：

1. 下载 `patch-6.6.63-rt46.patch.xz` → `dl/`
2. 过滤与 Ky 树冲突的 riscv 文件后打入内核
3. 再打 `vendor/patches/kernel/0001-riscv-enable-PREEMPT_RT-ky.patch`

详情见 `vendor/patches/kernel/README.md`。

关闭实时：

```bash
./bsp config KERNEL_RT=n
# 如需去掉 rt.config，可同时：
./bsp config KERNEL_EXTRA_FRAGMENTS="${PWD}/vendor/kernel-config/slim.config"
./bsp setup kernel --update   # 或重新 clone 干净树
./bsp kernel --clean
```

## 板端测试

rootfs 默认装 `rt-tests` / `stress-ng`，并提供：

```bash
sudo rt-latency-test          # 默认 10 万次 / 1ms
sudo rt-latency-test 200000 500
```
