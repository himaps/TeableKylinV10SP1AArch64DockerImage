# Teable 离线部署包 (Kylin V10 SP1 / aarch64)

为**银河麒麟 V10 SP1(aarch64)** 离线物理机构建可直接导入的 Teable Docker 部署包。
GitHub Actions 原生 arm64 runner 上打包，产物发布到 Releases，下载后拷入离线机一键部署。

仓库总索引见 [readme.md](readme.md)，通用打包手册见
[kylin-v10-sp1-aarch64-docker-instructions.md](kylin-v10-sp1-aarch64-docker-instructions.md)。

## 产物构成

`teable-offline-arm64-<版本>.tar.gz`，内含:

| 文件 | 说明 |
|---|---|
| `images/teable-offline-images-arm64.tar` | teable + postgres + redis 三个镜像(`docker load` 一次导入) |
| `docker-compose.yml` | 离线编排(全部使用本地镜像，零外网依赖) |
| `env.example` → `.env` | 配置模板(端口、密码、PUBLIC_ORIGIN) |
| `install.sh` / `uninstall.sh` | 一键部署 / 卸载 |
| `MANIFEST.txt` | 组件版本、镜像源与 digest |
| `SHA256SUMS.txt` | 包校验(与 tar.gz 同级) |

## 组件与版本对应(已逐一核实)

| 组件 | 来源 | 说明 |
|---|---|---|
| teable `1.10.0` | `registry.cn-shenzhen.aliyuncs.com/teable/teable-community:1.10.0-build.1141-arm64` | teable 官方 CI 推送的公开镜像源；`X.Y.Z-build.N` 与 GitHub release 一一对应，`-arm64` 为单架构 tag |
| postgres `15.4-alpine` | Docker Hub 官方镜像 | 多架构，runner 拉 arm64 |
| redis `7.2.4-alpine` | Docker Hub 官方镜像 | 多架构，runner 拉 arm64 |

teable 1.10.0 官方 standalone 编排即 teable + postgres + redis 三件套(应用启动时自带数据库迁移，无需独立 migrate 容器)。

## 构建(GitHub Actions)

1. Actions → **Build Teable arm64 offline bundle (Kylin V10 SP1)** → Run workflow
2. 参数：
   - `teable_build`：阿里云源的构建号(默认 `1.10.0-build.1141`，不含 `-arm64` 后缀)
   - `publish_release`：是否发布到 Releases
3. workflow 做四件事：拉取三镜像(带重试) → **断言架构全部为 arm64**(非 arm64 立即失败) → retag 为 `teable:<版本>` 后 `docker save` → 组装 bundle 并发布 Release(资产 + SHA256)

推送到 main 且改动涉及 `bundle/**` 或 workflow 本身时也会自动构建。
注意: push 触发时 dispatch inputs 为空，版本兜底值在 workflow 脚本里(与 input default 双写，改版本两处同步)。

## 离线机部署(Kylin V10 SP1)

前提：aarch64、内核 4.19+(V10 SP1 满足)、Docker 20.10+ 且有 compose v2 插件(或 docker-compose)、磁盘余量 3GB。

```bash
tar -xzf teable-offline-arm64-1.10.0.tar.gz
cd teable-offline
vim env.example        # 改掉 CHANGE_ME 密码(纯字母数字)
bash install.sh        # 导入镜像 → 生成 .env → compose up → 等待就绪
# 访问 http://<本机IP>:3000
```

局域网访问：`.env` 中 `PUBLIC_ORIGIN` 改为 `http://<内网IP>:3000`，并放行端口：
`firewall-cmd --add-port=3000/tcp --permanent && firewall-cmd --reload`。

升级：下载新版本包 → 覆盖解压 → `bash install.sh`(数据卷保留；升级前建议
`docker exec teable-db pg_dump -U teable teable > backup.sql`)。

## 为什么这个包在麒麟 V10 SP1 上能跑

- 容器自带完整用户空间，**宿主 glibc 2.31 不参与容器内程序运行**，唯一约束是宿主内核 syscall：
  - postgres 15 / redis 7.2 / Node.js 20 均兼容内核 4.19；
  - Node 20 的 libuv 在无 io_uring(内核 5.1+) 的内核上会自动回退，compose 里仍显式加 `UV_USE_IO_URING=0` 保险；
- `docker save` 产物为 docker-archive 格式，麒麟源里较旧的 docker 也能 `docker load`；
- 编排用 `version: '2.4'`，`depends_on: condition: service_healthy` 在旧版 docker-compose v1 与 Compose V2 下均可用。

## 踩坑记录(teable 专属)

- **阿里云源上不存在 `0.12.0`**(2026-10 全量分页核实，1950 个 tag 中无任何 `0.12*`)——早期 workflow 直接 pull 会失败。该源是官方 CI 推送，tag 形态为：
  - `X.Y.Z-build.N-amd64/-arm64`：稳定 release 构建(与 GitHub release 对应)
  - `X.Y.Z-alpha-build.N-amd64/-arm64`：alpha CI 构建
  - `release.<UTC时间>.N`：OCI 多架构 index(amd64+arm64)
  - `latest` / `latest-amd64` / `latest-arm64`：滚动 tag
- 镜像源还有 `teable/teable` 与 `teable/teable-db-migrate` 仓库；1.10.0 稳定版不需要 db-migrate(新版 main 分支的 compose 才拆出独立迁移容器)。
- 本网络(国内)无法直连 hub.docker.com/github.com，镜像源选择阿里云公开源可同时满足 CI 与本地核验；`tools/` 下的脚本用于匿名核验 manifest 架构与体积。

通用踩坑(各镜像共用)见打包手册 §5。
