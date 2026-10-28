#!/usr/bin/env bash
# ONLYOFFICE 在线协同编辑离线部署脚本 —— 银河麒麟 V10 SP1 / aarch64
# 栈: nginx(唯一入口) + nextcloud(用户/文件/共享) + documentserver(docx/xlsx 协同内核)
# 用法: bash install.sh
set -euo pipefail
cd "$(dirname "$0")"

err()  { echo "[错误] $*" >&2; exit 1; }
info() { echo "[信息] $*"; }

# ---- 环境检查 ----
[ "$(uname -m)" = "aarch64" ] || err "本包仅支持 aarch64 架构，当前为 $(uname -m)"
command -v docker >/dev/null 2>&1 || err "未安装 docker，请先安装麒麟源中的 docker-engine 或 Docker CE 20.10+"
docker info >/dev/null 2>&1 || err "docker 未运行，或当前用户无 docker 权限(用 sudo 运行，或将用户加入 docker 组)"

if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
else
  err "未找到 docker compose 插件或 docker-compose 命令"
fi
info "编排工具: $COMPOSE"

command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || \
  err "需要 curl 或 wget 命令用于就绪检测(麒麟基础版自带)"
http_get() { # $1=url -> 输出响应体
  if command -v curl >/dev/null 2>&1; then curl -s --max-time 8 "$1" || true
  else wget -q -O - -T 8 "$1" || true; fi
}

gen_secret() { tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 28; }

# ---- 导入镜像 ----
ls images/*-images-arm64.tar >/dev/null 2>&1 || \
  err "缺少镜像包 images/*-images-arm64.tar(分包下载时请先按说明 cat 合并再解压)"
info "导入镜像(重复导入幂等)..."
for t in images/*-images-arm64.tar; do docker load -i "$t"; done

# ---- 配置 ----
FRESH_ENV=0
if [ ! -f .env ]; then
  cp env.example .env
  FRESH_ENV=1
  info "已从 env.example 生成 .env"
fi

# 首次生成: 为占位项自动填随机密码(纯字母数字，redis/pgsql/compose 解析安全)
if [ "$FRESH_ENV" = 1 ]; then
  for k in POSTGRES_PASSWORD REDIS_PASSWORD JWT_SECRET NEXTCLOUD_ADMIN_PASSWORD; do
    if grep -q "^$k=CHANGE_ME$" .env; then
      sed -i "s|^$k=CHANGE_ME$|$k=$(gen_secret)|" .env
      info "已为 $k 自动生成随机密码(记录在 .env)"
    fi
  done
fi

# SERVER_IP: 仍是占位则自动探测本机内网 IP
if grep -q "^SERVER_IP=CHANGE_ME$" .env; then
  IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)
  [ -z "${IP:-}" ] && IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  [ -n "${IP:-}" ] || err "无法自动探测内网 IP，请编辑 .env 手动填写 SERVER_IP 后重跑"
  sed -i "s|^SERVER_IP=CHANGE_ME$|SERVER_IP=$IP|" .env
  info "已自动探测并写入 SERVER_IP=$IP"
fi

get_env() { grep -E "^$1=" .env | tail -1 | cut -d= -f2- | tr -d '[:space:]'; }
SERVER_IP=$(get_env SERVER_IP)
APP_PORT=$(get_env APP_PORT); APP_PORT=${APP_PORT:-80}
DS_VERSION=$(get_env DS_VERSION)
NC_VERSION=$(get_env NC_VERSION)
JWT_SECRET=$(get_env JWT_SECRET)
[ -n "$SERVER_IP" ] && [ "$SERVER_IP" != "CHANGE_ME" ] || err ".env 中 SERVER_IP 未配置"
[ -n "$DS_VERSION" ] && [ -n "$NC_VERSION" ] || err ".env 中缺少 DS_VERSION/NC_VERSION"

# 离线机没有仓库可回源: .env 版本必须与已导入镜像一致，早失败早发现
for pair in "documentserver:$DS_VERSION" "nextcloud:$NC_VERSION"; do
  name=${pair%%:*}; ver=${pair#*:}
  docker image inspect "$name:$ver" >/dev/null 2>&1 || \
    err "镜像 $name:$ver 不存在: .env 版本与 images/ 内镜像不一致(见 MANIFEST.txt)"
done

# ---- 数据目录与协同连接器 ----
mkdir -p data/nextcloud-data data/custom-apps data/fonts
if [ "$(id -u)" = "0" ]; then
  chown -R 33:0 data/nextcloud-data data/custom-apps 2>/dev/null || true
fi
if [ -d data/custom-apps/onlyoffice ]; then
  info "ONLYOFFICE 连接器已就位，跳过解压"
else
  APP_TAR=$(ls apps/onlyoffice*.tar.gz 2>/dev/null | head -1 || true)
  [ -n "$APP_TAR" ] || err "缺少协同连接器 apps/onlyoffice*.tar.gz"
  tar -xzf "$APP_TAR" -C data/custom-apps
  [ "$(id -u)" = "0" ] && chown -R 33:0 data/custom-apps 2>/dev/null || true
  info "已解压 ONLYOFFICE 连接器: $(basename "$APP_TAR")"
fi

if [ ! -d /usr/share/fonts/winfonts ]; then
  mkdir -p /usr/share/fonts/winfonts 2>/dev/null || true
  info "提示: 未检测到 /usr/share/fonts/winfonts，请将公文字体(仿宋_GB2312.ttf 等)拷入"
  info "      该目录，或拷入 $PWD/data/fonts ，然后重跑 bash install.sh 刷新字体缓存"
fi

# ---- 启动 ----
info "启动服务(首次启动 documentserver 内部初始化约 1~5 分钟)..."
$COMPOSE up -d

# ---- 就绪等待: 走 nginx 全链路探测 ----
BASE_URL="http://127.0.0.1:${APP_PORT}"

info "等待 nextcloud 就绪(最长 300 秒)..."
body=""
for _ in $(seq 1 60); do
  body=$(http_get "${BASE_URL}/status.php")
  echo "$body" | grep -q '"installed":true' && break
  sleep 5
done
echo "$body" | grep -q '"installed":true' || err "nextcloud 未就绪，查看: $COMPOSE logs nextcloud"

info "等待 documentserver 就绪(最长 450 秒)..."
hc=""
for _ in $(seq 1 90); do
  hc=$(http_get "${BASE_URL}/ds-vpath/healthcheck")
  [ "$hc" = "true" ] && break
  sleep 5
done
[ "$hc" = "true" ] || err "documentserver 未就绪，查看: $COMPOSE logs documentserver"
info "documentserver 健康检查通过(nginx 子路径反代链路正常)"

# ---- 配置协同连接器 ----
occ() { $COMPOSE exec -T -u www-data nextcloud php occ "$@"; }
BASE_EXT="http://${SERVER_IP}"
[ "$APP_PORT" != "80" ] && BASE_EXT="${BASE_EXT}:${APP_PORT}"

info "配置 ONLYOFFICE 协同连接器..."
occ config:system:set allow_local_remote_servers --value=true --type=boolean
occ app:enable onlyoffice || \
  err "连接器启用失败: 请确认 apps/ 下连接器版本与 nextcloud ${NC_VERSION} 兼容(见 MANIFEST.txt)"
occ config:app:set onlyoffice DocumentServerUrl --value="${BASE_EXT}/ds-vpath/"
occ config:app:set onlyoffice DocumentServerInternalUrl --value="http://documentserver/"
occ config:app:set onlyoffice StorageUrl --value="http://nextcloud/"
occ config:app:set onlyoffice jwt_secret --value="${JWT_SECRET}"
info "连接器已指向 ${BASE_EXT}/ds-vpath/"

# ---- 字体缓存 ----
info "刷新 documentserver 字体缓存..."
$COMPOSE exec -T documentserver fc-cache -f >/dev/null 2>&1 || \
  info "警告: 字体缓存刷新失败，公文字体可能未生效(见 README.txt 字体一节)"

docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
echo
echo "=============================================================="
echo " 部署完成"
echo "   访问地址: ${BASE_EXT}"
echo "   管理员:   .env 中 NEXTCLOUD_ADMIN_USER / NEXTCLOUD_ADMIN_PASSWORD"
echo "   验证协同: 管理员登录 -> 设置 -> ONLYOFFICE -> 连接状态应为『正常』;"
echo "             打开任意 docx/xlsx，另一账号同时打开即多人实时协同"
echo
echo " 字体校验:"
echo "   $COMPOSE exec documentserver fc-cache -fv"
echo "   $COMPOSE exec documentserver fc-list | grep 仿宋_GB2312"
echo
echo " 防火墙放行: firewall-cmd --add-port=${APP_PORT}/tcp --permanent && firewall-cmd --reload"
echo " 日志排查:   $COMPOSE logs -f documentserver | nextcloud | nginx"
echo "=============================================================="
