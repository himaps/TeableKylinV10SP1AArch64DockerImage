# ONLYOFFICE 协同编辑离线包 (readme-onlyoffice)

面向麒麟 V10 SP1 (aarch64) 离线内网环境的**多用户在线协同编辑 docx/xlsx** 全套部署包:
nginx(80 唯一入口) → nextcloud(用户/文件/共享) + onlyoffice documentserver(协同编辑内核)。
编辑内核与 MS Office 格式兼容度高，配合公文字体可保留排版；全链路 websocket 协同，
导入镜像后运行零外网。

Workflow: `.github/workflows/build-onlyoffice.yaml`(GitHub 原生 arm64 runner)。
包模板: `bundle-onlyoffice/`。

## 架构

```
浏览器(局域网)
   │  http://服务器IP (80 唯一入口)
   ▼
nginx ── /            → nextcloud(apache): 用户/文件/共享/回收站
   │   └─ /ds-vpath/  → documentserver: 编辑器静态资源 + 转换 API + 协同 websocket
   ▼                        │ (容器内自带 PostgreSQL/RabbitMQ/Redis，官方默认行为)
nextcloud ←─容器网络→ docs-db(postgres) + docs-cache(redis 文件锁)
```

- DS 以 `/ds-vpath/` 子路径对外: nginx `rewrite` 去前缀 + `X-Forwarded-Host: $host/ds-vpath`
  (ONLYOFFICE 官方 ds-vpath 方案)，DS 据此生成正确的编辑器资源绝对地址。
- 协同 websocket 走 `/ds-vpath/doc/{docId}/c/`，nginx 的 `Upgrade/Connection` 头与
  `proxy_read_timeout 600s` 是协同稳定的关键，不可删改。

## 组件版本(2026-10 核实)

| 组件 | 版本 | 来源 |
|---|---|---|
| documentserver | 8.3.3 | docker hub 官方**多架构**镜像 `onlyoffice/documentserver:8.3.3`，`--platform linux/arm64` 拉取(实测 manifest 含 amd64+arm64) |
| nextcloud | 30.0.12-apache | docker hub 官方多架构镜像 |
| postgres / redis | 15.4-alpine / 7.2.4-alpine | 同 teable 包，物理机已验证 |
| nginx | 1.27-alpine | 官方多架构镜像 |
| onlyoffice 连接器 | v10.2.1 | github.com/ONLYOFFICE/onlyoffice-nextcloud releases(打包时下载进包) |

版本选择原则: 全部用多年多架构正式版，不追新; workflow dispatch 参数可换版本重打。

## 为什么不是 DocSpace(豆包原方案核查结论)

豆包给的 `docspace + documentserver + postgres + nginx` 四容器方案**按原文无法部署**:

| # | 原方案写法 | 核实结论 |
|---|---|---|
| 1 | `onlyoffice/docspace:3.7.0-arm64` | 该 tag 不存在(registry 实测 403)。DocSpace 官方镜像 tag 无 `-arm64` 后缀体系; `latest` 虽含 arm64 manifest，但 3.x 官方部署形态是十余个微服务容器(studio/socket/files/backup/notify + rabbitmq/redis/elasticsearch...)，缺服务起不来 |
| 2 | `onlyoffice/documentserver:latest-arm64` | 仅 `latest-arm64` 存在，`X.Y.Z-arm64` 不存在; 正确姿势是多架构 manifest + `--platform linux/arm64` |
| 3 | 未处理麒麟 seccomp | 麒麟 V10 + 老 docker(20.10.x) 默认 seccomp 拦截 DS 容器内 PostgreSQL 系统调用导致反复重启(ONLYOFFICE 论坛同款案例)，官方解法 `seccomp=unconfined` 或 docker ≥23。本包已在 compose 内置 |
| 4 | nginx 只反代 `/doc/` | DS 静态资源在 `/web-apps/` `/sdkjs/` `/cache/` 等根路径，只代 `/doc/` 编辑器白屏。已改官方 ds-vpath 方案 |
| 5 | `DOCSPACE_URL: [http://...](http://...)` | 豆包输出 markdown 伪影，照抄必错 |

取舍: DocSpace 在 aarch64 无稳妥官方路径且官方建议 8GB+ 内存; 本包改用
nextcloud 做用户/文件层 + 同一个 DS 编辑内核，排版保真不变，资源减半，
全部组件为久经验证的多架构镜像。

## 部署(离线机)

```bash
# 分包下载时: cat onlyoffice-offline-arm64-*.tar.gz.part-* > bundle.tar.gz
sha256sum -c SHA256SUMS.txt
tar -xzf onlyoffice-offline-arm64-*.tar.gz && cd onlyoffice-offline
bash install.sh     # 自动: 导入镜像/生成 .env+随机密码/探测内网IP/解压连接器/启动/配置协同
```

install.sh 幂等，可重复执行。就绪探测走 nginx 全链路:
`GET /status.php` (nextcloud) + `GET /ds-vpath/healthcheck` (DS)。

访问 `http://<内网IP>`，管理员账号在 `.env`；验证协同: 设置 → ONLYOFFICE →
连接状态『正常』；两个账号同开一个 docx 即实时协同。

## 字体

默认只读挂载宿主机 `/usr/share/fonts/winfonts` 与 `/usr/share/fonts`(→容器
`/usr/share/fonts/kylin`)；追加字体放 `./data/fonts`。之后:

```bash
docker compose exec documentserver fc-cache -fv
docker compose exec documentserver fc-list | grep 仿宋_GB2312
```

## 已知限制与注意

- DS 容器内自带数据库(官方默认行为)，为规避麒麟 seccomp 问题已配
  `security_opt: seccomp=unconfined`，离线内网环境风险可控；docker ≥23 可移除。
- `deploy.resources.limits` 在老版 docker-compose(v1 python) 下不生效，
  故用 `mem_limit`(DS 4G / nextcloud 2G)，CPU 不硬限。
- 换服务器 IP: 改 `.env` 的 `SERVER_IP` 后重跑 `bash install.sh`(同步连接器地址)。
- 重建过 nextcloud 容器后若 502，`docker compose restart nginx`
  (nginx 启动时缓存了上游容器 IP)。
- 内存建议 8GB+；磁盘 12GB+。

## 构建参数(workflow_dispatch)

| 参数 | 默认 | 说明 |
|---|---|---|
| ds_version | 8.3.3 | documentserver 多架构 tag(不带 -arm64 后缀) |
| nc_version | 30.0.12 | nextcloud `-apache` 变体版本号 |
| connector_version | v10.2.1 | 连接器 GitHub release tag |
| publish_release | true | 是否发 Release(push 触发恒发布) |

> push 触发时 dispatch inputs 为空，**默认值双写必须同步改**(workflow input default
> 与 Resolve versions 步骤的兜底值)，教训同 readme.md 统一约定。

CI 关卡: 连接器载荷自检 → pull 3 次重试 → arm64 架构断言 → save 载荷自检 →
compose `config -q` + nginx `nginx -t` 语法校验 → >2GiB 自动 1900MB 分包 →
artifact(7 天) + Release(`gh release upload --clobber` 回退)。
