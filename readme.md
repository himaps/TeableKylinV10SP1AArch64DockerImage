# Kylin V10 SP1 (aarch64) Docker 镜像仓库

面向**银河麒麟 V10 SP1 (aarch64) 离线物理机**的 Docker 镜像构建工厂与镜像集:
在 GitHub Actions 原生 arm64 runner 上拉取/构建镜像，打成零外网依赖的离线部署包
发布到 Releases，下载后拷入离线机一键导入。

仓库计划更名为 `kylin-v10-sp1-aarch-docker-hubs`，作为存放、构建不同类型镜像的
枢纽：每种镜像一套 workflow + 包模板 + 分册文档，后续新镜像按同一套约定增补。

## 镜像目录

| 镜像 | 用途 | 最新版本 | 分册文档 |
|---|---|---|---|
| teable (+postgres/redis) | 多维表格离线部署包(含 compose/install.sh 一键部署) | [v1.10.0-arm64](https://github.com/himaps/TeableKylinV10SP1AArch64DockerImage/releases/tag/v1.10.0-arm64) | [readme-teable.md](readme-teable.md) |
| builder | 编译沙箱(build-essential/gcc/clang/cmake/40+开发库)，物理机挂源码目录进容器编译 | [builder-v1.1.0](https://github.com/himaps/TeableKylinV10SP1AArch64DockerImage/releases/tag/builder-v1.1.0) | [readme-builder.md](readme-builder.md) |

新镜像在此表登记。

## 所有镜像包的统一约定

- 产物: `<name>-offline-arm64-<版本>.tar.gz` + `SHA256SUMS.txt`，Release 单资产 ≤ 2 GiB；
- 包内必有: `images/*.tar`(`docker load` 一次导入)、`README.txt`(面向部署人的说明)、
  `MANIFEST.txt`(组件版本/来源/digest/工具链实查)；部署型另有
  `docker-compose.yml` + `env.example` + `install.sh`/`uninstall.sh`；
- CI 必过关卡: pull 3 次重试 → **arm64 架构断言** → `docker save` 后 tar 载荷自检 →
  artifact(7 天) + Release(`gh release upload --clobber` 回退)；
- 触发: 手动 workflow_dispatch(带参数) + push(按各自目录 paths 过滤，互不误触发)；
- push 触发时 dispatch inputs 为空，**版本兜底值与 input default 双写必须同步改**
  (踩过坑: 兜底没同步，push 构建以旧版本号出包并覆盖旧 release 资产)。

## 新增一种镜像

复制现有 workflow + 包模板，按
[kylin-v10-sp1-aarch64-docker-instructions.md](kylin-v10-sp1-aarch64-docker-instructions.md)
执行: 核验镜像 arm64 存在性与内核 4.19 兼容性 → 改 workflow/包模板 → CI 验证 →
物理机验收 → 在上表登记并新增 `readme-<name>.md` 分册。

## 文档地图

- [kylin-v10-sp1-aarch64-docker-instructions.md](kylin-v10-sp1-aarch64-docker-instructions.md)
  —— 通用打包手册(适配红线/打包步骤/checklist/踩坑记录)
- [readme-teable.md](readme-teable.md) / [readme-builder.md](readme-builder.md) —— 各镜像分册
- 各离线包内 `README.txt` —— 面向离线机部署人的操作说明

## 仓库结构

```
.github/workflows/build.yaml          teable 部署包流水线(arm64 runner)
.github/workflows/build-builder.yaml  构建环境镜像(builder)流水线
bundle/                        teable 离线包内容模板(compose/env/脚本/包内说明)
builder/                       构建环境镜像模板(Dockerfile + 包内说明)
tools/inspect-manifests.sh     核验镜像源 manifest 架构
tools/image-size.py            核验镜像压缩体积
tools/watch-ci.py              匿名轮询 CI 状态(硬编码仓库路径，更名后需同步改)
readme-teable.md               teable 分册
readme-builder.md              builder 分册
kylin-v10-sp1-aarch64-docker-instructions.md   通用打包手册
```

## 更名注意

仓库更名为 `kylin-v10-sp1-aarch-docker-hubs` 后: GitHub 对旧路径的 git/API 访问会
自动重定向，不影响既有 release 链接与 CI；但 `tools/watch-ci.py` 硬编码的仓库路径
建议同步改准，本文档中的绝对链接也可顺手替换。
