# Docker 编译环境（A733）

把 A733 的构建依赖固化在镜像里，避免每台机器装一堆包（等价于 `./bsp env` 做的事）。

## 构建镜像

```bash
docker build --network host -t microduck-a733 -f docker/Dockerfile .
```

> 容器里 apt 走宿主代理：构建时用 `--network host`，并给 docker 守护进程配好
> `HTTP_PROXY/HTTPS_PROXY`（或 `--build-arg http_proxy=...`）。

## 编译内核

```bash
docker run --rm --network host -v "$PWD":/work -w /work microduck-a733 \
    bash -lc './bsp config PLATFORM=a733 && ./bsp setup && ./bsp kernel'
```

产物在 `out/a733/kernel/`：`Image` 和 `sun60i-a733-cubie-a7z.dtb`。

## 其它

- rootfs（`./bsp rootfs`）需要在容器里有 `debootstrap` + `qemu-user-static`，镜像里已装；
  但 `mkfs.ext4 -d` 和 loop 设备在容器里可能受限，建议 rootfs 仍在宿主上构建。
- u-boot 的 brandy 构建需要 Allwinner 自己的工具链/子模块，镜像不包含，仍按
  `vendor/a733/README.md` 的说明在宿主上做。
- 不想每次拉源码可以把 `sources/` 挂在容器的 `/work/sources`（`./bsp setup` 会跳过已存在的仓库）。

## 在 WSL2 里跑 Docker 的注意点（已验证）

WSL2 没有 systemd 时手动起 dockerd，并且要用 `vfs` 存储驱动——默认的 overlayfs 在
export 镜像层时会因为 `drvfs/9p` 的 xattr 问题失败（`failed to get xattr ... rbash`）：

```bash
dockerd --iptables=false --ip6tables=false --bridge=none \
        --storage-driver=vfs --data-root=/var/lib/docker-vfs &
```

容器用 `--network host`（bridge 被关掉了），拉镜像/apt 走宿主的代理：
`HTTP_PROXY=http://127.0.0.1:15732` 给 dockerd，`-e http_proxy=...` 给容器。

另外 Dockerfile 里用的是 `CMD` 而不是 `ENTRYPOINT`，这样 `docker run ... IMAGE bash -lc '...'`
才是「在容器里执行 bash」；用 `ENTRYPOINT ["/bin/bash"]` 时 `bash` 会变成 bash 的第一个参数，
报 `cannot execute binary file`。

`./bsp` 现在还会在启动时检查脚本是不是 CRLF（Windows 检出）并自动转成 LF，容器里直接跑
不会再报 `$'\r': command not found`。
## 已验证（2026-10-23，WSL2 + Docker 29.1.3）

- `docker build`：`microduck-a733` 镜像 **772 MB**（vfs 存储驱动）；
- `docker run ... ./bsp kernel` 端到端跑通（exit 0），产出：
  - `out/a733/kernel/Image`：**37 MB**
  - `out/a733/kernel/sun60i-a733-cubie-a7z.dtb`：**157536 字节**

首次 clone（u-boot 200MB + kernel 6.6 1.5GB + bsp 80MB + device 5MB）加全量内核编译
约 25 分钟；之后增量编译 **约 11 秒**（dtb 改成 cpp+dtc，不再 make dtbs）。

`A733_KERNEL_COMPRESS=lz4` 时额外产出 `Image.lz4`（37.7 MB → **14.7 MB**，39%），
给带 lz4 命令的 u-boot 用。

构建过程中 `./bsp kernel` 会自动处理 6.6 BSP 的几个构建前提（详见
`vendor/a733/README.md` 的「内核构建的坑」）：`BSP_TOP`、`LICHEE_KERN_DIR`、
`sunxi-autogen.h`、`DTC_INCLUDE`、关掉主线的 `SUNXI_CCU`、关掉 rt-media。