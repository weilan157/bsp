# rockchip-bsp

独立仓库：从 GitHub 拉取官方 `rockchip-linux/u-boot` 与 `rockchip-linux/rkbin`，在主机上编译 RK3576 U-Boot。**不依赖泰山派 SDK 或任何 SDK 脚本/工具链。**

## 目录结构

```
rockchip-bsp/
├── config.env.example    # 配置模板（复制为 config.env）
├── scripts/
│   ├── init-env.sh       # 安装编译依赖 + gcc-aarch64-linux-gnu
│   ├── setup-sources.sh  # clone GitHub u-boot / rkbin
│   ├── build-uboot.sh    # 编译 loader / uboot / trust
│   └── setup-all.sh      # 一键：环境 + 源码 + 编译
├── backup/               # 可选本地 rkbin 快照（脚本生成，不入库）
└── sources/              # u-boot / rkbin 克隆目录（不入库）
```

## 快速开始

```bash
cd /data/rockchip-bsp
cp config.env.example config.env
# 按需修改 GitHub 分支、交叉链前缀等

./scripts/setup-all.sh          # 初始化环境、拉源码、编译
# 或分步：
./scripts/init-env.sh
./scripts/setup-sources.sh
./scripts/build-uboot.sh
```

## 编译产物

成功后在 `sources/u-boot/` 下生成例如：

- `uboot.img`
- `trust.img`
- `rk3576_spl_loader_*.bin`
- `rk3576_idblock_*.img`

## 与 SDK 的关系

| 项目 | rockchip-bsp | 泰山派 SDK |
|------|--------------|------------|
| U-Boot 源码 | GitHub `rockchip-linux/u-boot` | SDK 内 vendor 树 |
| rkbin | GitHub `rockchip-linux/rkbin` | SDK 内 rkbin（版本可能不同） |
| 工具链 | apt `gcc-aarch64-linux-gnu` | SDK `prebuilts/` |
| Recovery OTA / boot.img / rootfs | **不在此仓库** | SDK `./build.sh` |

请勿混烧不同来源的 loader/trust 与 SDK 产物，除非已核对 BL31/SPL 等版本一致。

泰山派需 `--spl-new`（脚本已包含）。

## 可选配置

- `TOOLCHAIN_BIN`：使用自定义工具链 bin 目录，而非 apt 默认链。
- `RKBIN_BACKUP_SRC`：clone 前将**任意本地** rkbin 目录 rsync 到 `backup/`（与 SDK 无关联，仅作对照快照）。

## 分支

- `main`：仓库骨架
- `rk3576`：RK3576 相关脚本与配置

## 远程仓库

```bash
git remote add origin git@github.com:weilan157/rockchip-bsp.git
git push -u origin rk3576
```
