# 麒麟 V10 SP1 (aarch64) 离线 Docker 镜像打包指南

> 本指南从 Teable 1.10.0 离线包的实际构建与物理机验证(2026-10)中提炼，是给"下一款软件"用的
> 通用操作手册。为新软件打包时，以本仓库为蓝本复制结构，按第 3 节逐项替换。
> 蓝本流水线: `.github/workflows/build.yaml` + `bundle/` 模板 + `tools/` 核验脚本；
> "构建环境型"镜像的变体见 §7(蓝本 `builder/` + `.github/workflows/build-builder.yaml`)。
> 仓库计划更名为 `kylin-v10-sp1-aarch-docker-hubs`(多镜像枢纽，总索引见根 readme.md)。

## 1. 目标与产出形态

**场景**: 目标机是**离线**的银河麒麟 V10 SP1 aarch64 物理机(仅麒麟 yum 源可用、无外网)，
需要在其 Docker 上运行业务软件。

**前提**: 软件官方(或可信镜像源)已提供 aarch64 镜像。本流水线只做"拉取 → 打包 → 发布"，
不做交叉编译；若根本没有 arm64 镜像，需另行自行构建，不在本指南范围。

**产出**: 一个 `tar.gz` 离线部署包，拷入离线机解压后 `bash install.sh` 一键完成
导入镜像 + 生成配置 + 启动 + 就绪等待。包内结构(模板见 `bundle/`):

```
<app>-offline/
├── images/<app>-offline-images-arm64.tar   # 全部镜像，docker load 一次导入
├── docker-compose.yml                      # 纯本地镜像编排，零外网依赖
├── env.example                             # 配置模板(install.sh 首次运行复制为 .env)
├── install.sh / uninstall.sh
├── README.txt                              # 面向部署人的包内说明
└── MANIFEST.txt                            # 组件版本、来源、digest(CI 自动生成)
```

**发布路径**: GitHub Actions 在原生 arm64 runner 上打包 → Release 资产 + SHA256SUMS
→ 人工下载拷入离线机。

## 2. 为什么这个形态能在麒麟 V10 SP1 上跑(适配红线)

红线决定技术选型，换软件时逐条核对:

1. **宿主唯一硬约束是内核 4.19，不是 glibc。** 容器自带完整用户空间，宿主 glibc 2.31
   不参与容器内程序运行，所以容器内用 Ubuntu/Debian/Alpine 基底都行；但要核对软件
   运行时对内核特性的要求:
   - io_uring 内核 5.1+ 才有 → Node.js/libuv 应用在 compose 里显式设 `UV_USE_IO_URING=0`
     (libuv 本身会自动回退，设了保险)；
   - cgroup v2、较新的 eBPF 特性在 4.19 上不可用或受限，涉及时单独验证；
   - 已验证兼容 4.19 的常见栈: postgres 15 / redis 7.x / Node 20 / Go / Java 8+。
2. **编排必须兼容旧版 compose。** 用 `version: '2.4'`；`depends_on: condition:
   service_healthy` 在麒麟源的 docker-compose v1 与新版 Compose V2 下都可用。
   不要用 V2 独有新语法。
3. **`docker save` 的 docker-archive 格式**，麒麟源里较旧的 docker-engine 也能
   `docker load`(不用 OCI 布局导出)。
4. **包内零外网依赖**: compose 中所有 image 都来自随包 tar，不引用任何 registry；
   install.sh 的就绪探测只走本机回环。
5. **必须断言 arm64**: CI 里对每个镜像 `docker image inspect --format
   '{{.Architecture}}'` 必须等于 arm64，防止多架构 tag 解析错位时打出 x86 包。
6. **Release 单资产上限 2 GiB**，打包前先预估压缩体积(见 §4 工具)。
7. **运行在 GitHub 原生 arm64 runner(`ubuntu-24.04-arm`，公开仓库免费)上**，
   直接 pull 预构建镜像，全程不需要 buildx/QEMU 交叉模拟。

## 3. 新软件打包步骤

### 3.1 确定镜像清单与版本(动手改代码前先做完这一步)

1. **列组件栈**: 对照软件**对应版本的官方部署编排**(docker-compose/helm)确定需要哪几个
   容器(app/db/cache/独立迁移容器等)。注意官方新版本可能拆出独立 migrate 容器或改掉
   依赖关系，以目标版本的官方编排为准，不要凭印象。
2. **确定每个镜像的来源与 arm64 形态**:
   - 优先官方多架构镜像(Docker Hub): CI runner 可直连，`docker pull --platform
     linux/arm64` 自动取 arm64；
   - 国内网络(本地核验用)无法直连 hub.docker.com，可改用国内公开镜像源(如阿里云)，
     但必须核实该源确为官方 CI 推送(对照官方发布说明/digest)，并弄清其 tag 命名规则——
     CI 推送的源常见 `X.Y.Z-build.N-amd64/-arm64`、`release.<UTC>.N`(多架构 index)、
     `latest-*` 等形态，**别假设 `X.Y.Z` 裸版本 tag 一定存在**。
3. **核验 arm64 存在性与体积**(方法见 §4)，并记录结论到仓库 readme(来源、tag 规则、
   核实日期)——下次升级照抄即可，不用重新调研。
4. **版本 pin 一次定死**: workflow 的 env 与 `bundle/docker-compose.yml` 中的 image
   各写一份，**两处必须同步改**(两处都留注释互相提醒)。

### 3.2 改造 workflow(`.github/workflows/build.yaml`)

以本仓库 build.yaml 为模板，替换点:

| 位置 | teable 中的值 | 换成 |
|---|---|---|
| `workflow_dispatch.inputs.*` | `teable_build` 构建号参数 | 软件的版本/构建号参数(保留正则校验 `^[A-Za-z0-9._-]+$`) |
| `env.MIRROR` | 阿里云 teable 源 | 软件镜像源(官方多架构镜像则删掉，直接写 image 名) |
| `env.POSTGRES_IMAGE` / `REDIS_IMAGE` | 15.4-alpine / 7.2.4-alpine | 实际依赖组件(没有的删掉) |
| Pull / Verify / Save 三个 step 的镜像列表 | 三个镜像 | 实际清单(pull 带 3 次重试) |
| Retag 规则 | `teable:<版本>` | `<app>:<版本>`(应用镜像 retag 去掉 registry 前缀；db/cache 等基础组件保留原名，compose 直接引用) |
| 资产名 / MANIFEST / Release notes | `teable-offline-arm64-<版本>.tar.gz` | 保持 `<app>-offline-arm64-<版本>.tar.gz` 命名法，notes 捆组件表 |

**必须保留的机制**(都踩过坑):

- pull 3 次重试(arm64 runner 偶发网络抖动)；
- 架构断言 step(§2 第 5 条)；
- `docker save` 后 `tar -tf | grep manifest.json` 载荷自检(防空包)；
- `upload-artifact`(7 天留存，供不发 Release 的试构建) + `gh release create`
  3 次重试、失败回退 `gh release upload --clobber`(tag 已存在时追加资产)；
- push 触发用 `paths` 限定 `bundle/**` 和 workflow 本身，避免改文档也触发大构建。

### 3.3 改造 bundle 模板(`bundle/` 五件套)

- **docker-compose.yml**: 保持 `version: '2.4'`；所有 service 用本地导入的镜像；
  必填配置用 `${VAR:?请在 .env 中设置}` 兜底；db/cache 加 healthcheck，app 的
  `depends_on` 用 `condition: service_healthy`；数据全部落 named volume；宿主端口
  只映射必要的；Node 应用加 `UV_USE_IO_URING=0`。
- **env.example**: 密码用 `CHANGE_ME_*` 占位，**写明密码必须纯字母数字**(`$` 等特殊
  字符会被 compose 做变量替换而损坏)；对外地址 `PUBLIC_ORIGIN` 默认 `127.0.0.1`，
  注释说明局域网访问要改成内网 IP。
- **install.sh**: 整体流程保留——架构检查(`uname -m`) → docker 存在/运行检查 →
  compose 探测(`docker compose` 插件优先，回退 `docker-compose` v1) → `docker load`
  → 生成 `.env` + CHANGE_ME 提醒 → `up -d` → 180 秒就绪探测(curl/wget) → 防火墙
  提示。需替换的就三处: 就绪探测的 URL/端口、`docker ps` 展示、`.env` 变量名。
- **uninstall.sh**: 通常不用改(`down` 默认保留数据卷，`--purge` 连卷删除)。
- **README.txt**: 包内容/前提条件/部署步骤/常用命令/数据卷位置/升级方法/FAQ，
  按软件替换服务名与端口。

### 3.4 构建与验收

1. 手动触发: Actions → Run workflow 填版本参数。**先 `publish_release=false` 试构建**，
   从 artifact 验证包内容无误后再正式发布。
2. CI 必过的四道关卡: pull 成功 → 架构断言全 arm64 → tar 自检含 manifest.json →
   打包上传完成。
3. Release 下载后: `sha256sum -c SHA256SUMS.txt` 校验；有条件先在任意机器
   `docker load` 后 `docker image inspect` 确认架构。

### 3.5 离线机部署与验收

前提: aarch64、内核 4.19+、Docker 20.10+ 且有 compose、磁盘余量 ≥ 镜像体积×2 + 数据预估。

```bash
tar -xzf <app>-offline-arm64-<版本>.tar.gz
cd <app>-offline
vim env.example        # 改掉 CHANGE_ME 密码(纯字母数字)
bash install.sh        # 导入镜像 → 生成 .env → 启动 → 就绪等待
```

验收清单:

- [ ] `docker ps` 各容器 Up (healthy)；
- [ ] 本机 `curl http://127.0.0.1:<port>/` 返回正常；
- [ ] 局域网访问: `.env` 的 `PUBLIC_ORIGIN` 改内网 IP，并放行端口
      `firewall-cmd --add-port=<port>/tcp --permanent && firewall-cmd --reload`；
- [ ] 重启物理机后容器自恢复(依赖 compose 的 `restart: always`)。

升级: 新包覆盖解压 → `bash install.sh`(数据卷保留)；升级前先备份数据库卷
(如 `docker exec <db容器> pg_dump -U <user> <db> > backup.sql`)。
回滚: 保留旧版本包，`uninstall.sh` 后用旧包重装；跨大版本回滚涉及 schema 兼容性，
不可靠，只能恢复备份。

## 4. 核验工具(`tools/`)

| 脚本 | 用途 | 用法 |
|---|---|---|
| `inspect-manifests.sh` | 查阿里云源某 tag 的 manifest 类型与各架构 digest | `bash tools/inspect-manifests.sh <tag>...` |
| `image-size.py` | 查镜像压缩层体积(自动跟随 index 取 arm64 条目) | `python tools/image-size.py <repo>:<tag>...` |
| `watch-ci.py` | 匿名轮询本仓库 commit 的 check-run 状态 | `python tools/watch-ci.py <sha> [次数] [间隔秒]` |

换软件后要改脚本内的 `REGISTRY`/`REPO` 或 `watch-ci.py` URL 中的仓库路径。
三个脚本都带 SSRF 防护(仅 https、host 白名单、解析 IP 拒绝内网/保留段、不跟随重定向)，
改 host 时同步改 `ALLOWED_HOSTS`。

## 5. 踩坑记录(通用)

1. **裸版本 tag 不一定存在**: CI 推送的镜像源 tag 形态多样，先全量分页核实再写
   workflow(teable 的 `0.12.0` 就不存在，直接 pull 必挂)。
2. **compose 变量替换吃 `$`**: 密码含 `$` 会在 env/compose 替换时损坏，密码纯字母数字。
3. **旧版 compose 兼容面**: `version: '2.4'` + `condition: service_healthy` 是
   docker-compose v1 与 Compose V2 的公共子集；install.sh 探测顺序为
   `docker compose` 插件优先、`docker-compose` v1 回退。
4. **io_uring**: 内核 4.19 无 io_uring(5.1 引入)，Node/libuv 应用显式关闭。
5. **Release 资产 2 GiB 上限**；`upload-artifact` 7 天留存仅作中间产物，正式交付靠 Release。
6. **`gh release create` 撞已有 tag 会失败**: 重试 3 次后回退
   `gh release upload --clobber` 追加覆盖资产。
7. **空包风险**: `docker save` 前确认镜像已拉取成功，save 后 `tar -tf` 自检含
   `manifest.json`。
8. **本地核验与 CI 网络环境不同**: 本地(国内)直连不了 Docker Hub/GitHub，核验走
   国内源 + registry API 匿名 token；CI(arm runner)直连没问题。两条路径都要能独立核验，
   结论(尤其 tag 存在性)以 registry API 实查为准，不以文档或印象为准。
9. **push 触发时 `inputs.*` 全为空**: workflow_dispatch 的 input default 只对手动触发
   生效，push/自动触发走的是 step 脚本里的 `${VAR:-兜底值}`——两处双写必须同步改
   (实际踩过: 改了 input default 没改兜底，push 构建以旧版本号出包)。且
   `gh release upload --clobber` 回退会**覆盖**同名 release 的既有资产，版本号打错
   时旧资产会被静默替换——push 构建后要核对 release 资产体积/内容是否与预期一致。

## 6. 新软件打包 Checklist(速查)

**改代码前**
- [ ] 官方编排确认组件栈与各组件版本
- [ ] 每个镜像的 arm64 存在性与 tag 规则核实完毕(记录来源与核实日期)
- [ ] 运行时对内核 4.19 的兼容性核对(io_uring / cgroup v2 / eBPF)
- [ ] 压缩体积预估 < 2 GiB

**改代码时**
- [ ] workflow: inputs / env / 镜像清单 / retag / 资产名 / release notes 全部替换
- [ ] 版本 pin 双写处(workflow env 与 bundle/docker-compose.yml)同步
- [ ] bundle: compose / env.example / install.sh / README.txt 的服务名、端口、路径替换
- [ ] tools 脚本的 REGISTRY / REPO / 仓库路径更新

**验收**
- [ ] CI 绿(架构断言 + tar 自检通过)
- [ ] SHA256 校验通过
- [ ] 离线物理机 `install.sh` 跑通: 容器 healthy、HTTP 可达、重启自恢复
- [ ] 仓库 readme 更新本软件的组件版本对应表

## 7. 变体: 构建环境镜像(builder)

§3 的 teable 是"部署型"包(应用 + 依赖服务 + compose 编排)。另一类需求是**构建环境**
镜像: 离线物理机把它当编译沙箱用(`docker run` 挂载源码目录编译)，没有服务编排，
物理机也不需要装编译器。蓝本: `builder/Dockerfile` +
`.github/workflows/build-builder.yaml`。与 §3 流程的差异:

- **基座选择是核心决策，依据是"产物要不要跑在宿主机"**:
  - 产物要在宿主机直接运行 → 基座 glibc 必须 ≤ 宿主 glibc。麒麟桌面 V10 SP1 为
    glibc 2.31 → `ubuntu:20.04`(glibc 恰为 2.31)或 `debian:bullseye`；
    用 ubuntu:22.04+(glibc 2.35)编出的产物在宿主上会报
    `GLIBC_2.34' not found`；
  - 产物只在容器内运行 → 基座随意，可用更新的 22.04/24.04 换新工具链；
  - C++ 产物另受 libstdc++ 版本影响，宿主报 libstdc++ 错误时加
    `-static-libstdc++ -static-libgcc` 或回容器内运行。
- **打包流程换成 `docker build`**(Dockerfile 驱动，apt 装 build-essential/g++/cmake
  等)，其余机制(基座 pull 3 次重试、架构断言、save 后 tar 自检、MANIFEST、
  artifact + Release)照旧。workflow 的 `extra_packages` 参数可在不改文件的情况下
  追加 apt 包——离线机无法后期补装，镜像要一次装全。
- **bundle 精简为三件**: `images/*.tar` + `README.txt` + `MANIFEST.txt`，没有
  compose/env.example/install.sh，导入就是一条 `docker load`；用法写在 README
  (挂载 `$PWD` 到 `/src`、`-u "$(id -u):$(id -g)"` 避免产物属 root)。
- MANIFEST 除基座 digest 外，记录**容器内实查**的工具链版本
  (gcc/g++/make/cmake/git/python3 --version)与基座 glibc(`ldd --version`)，
  作为"产物兼容性"的凭据。
- 踩坑补充: focal 的 git 2.25 无 safe.directory 检查(2.35.2 引入)，挂载目录不存在
  dubious ownership 报错；换更新基座时需在镜像里
  `git config --system --add safe.directory '*'`。
