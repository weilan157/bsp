# rockchip-bsp

在主机上从 GitHub 拉取官方 `rockchip-linux/u-boot` 与 `rockchip-linux/rkbin`，编译 RK3576 U-Boot，并保留泰山派 SDK 自带 `rkbin` 快照备份。

## 目录结构

```
rockchip-bsp/
├── config.env.example    # 配置模板（复制为 config.env）
├── scripts/
│   ├── init-env.sh       # 安装编译依赖
│   ├── setup-sources.sh  # 备份 SDK rkbin + clone GitHub 源码
│   ├── build-uboot.sh    # 编译 RK3576 loader / uboot / trust
│   └── setup-all.sh      # 一键：环境 + 源码 + 编译
├── backup/               # SDK rkbin 备份（脚本生成，不入库）
└── sources/              # u-boot / rkbin 克隆目录（不入库）
```

## 快速开始

```bash
cd /data/rockchip-bsp
cp config.env.example config.env
# 按需修改 config.env 中的 TSPI_SDK_ROOT

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

## 分支

- `main`：仓库骨架
- `rk3576`：RK3576 / 泰山派相关脚本与配置

## 远程仓库

```bash
git remote add origin git@github.com:weilan157/rockchip-bsp.git
# 已有 https 远程时改为 SSH：
# git remote set-url origin git@github.com:weilan157/rockchip-bsp.git
git push -u origin main
git push -u origin rk3576
```

## 注意

- 编译使用 **GitHub rkbin**；SDK rkbin 仅作 **只读备份** 对照，请勿混用版本除非你知道差异。
- 泰山派需 `--spl-new`（脚本已包含），与 SDK `RK_UBOOT_SPL=y` 一致。
- 首次 `setup-sources.sh` 会 `git clone`，需要网络。
