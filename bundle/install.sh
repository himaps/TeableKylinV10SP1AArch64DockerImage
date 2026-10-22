#!/usr/bin/env bash
# Teable 离线部署脚本 —— 银河麒麟 V10 SP1 / aarch64
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

# ---- 导入镜像 ----
IMAGES_TAR="images/teable-offline-images-arm64.tar"
[ -f "$IMAGES_TAR" ] || err "缺少镜像包 $IMAGES_TAR(解压需保留目录结构)"
info "导入镜像(约 1~3 分钟)..."
docker load -i "$IMAGES_TAR"

# ---- 配置 ----
if [ ! -f .env ]; then
  cp env.example .env
  info "已从 env.example 生成 .env"
fi
if grep -q "CHANGE_ME" .env; then
  info "提醒: .env 中仍是 CHANGE_ME 占位密码。多人/跨网段环境请先修改密码再继续(单机试用可直接回车继续)"
  read -r -p "按回车继续，Ctrl+C 退出修改..." _
fi

APP_PORT=$(grep -E '^APP_PORT=' .env | tail -1 | cut -d= -f2- | tr -d '[:space:]')
APP_PORT=${APP_PORT:-3000}

# ---- 启动 ----
info "启动服务..."
$COMPOSE up -d

# ---- 就绪等待 ----
info "等待服务就绪(最长 180 秒)..."
probe() {
  if command -v curl >/dev/null 2>&1; then
    curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${APP_PORT}/" || true
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O /dev/null "http://127.0.0.1:${APP_PORT}/" && echo 200 || echo 000
  else
    echo 000
  fi
}
for _ in $(seq 1 60); do
  code=$(probe)
  if [ "$code" != "000" ] && [ "$code" -lt 500 ] 2>/dev/null; then
    info "Teable 已就绪: http://127.0.0.1:${APP_PORT}/ (HTTP ${code})"
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
    info "局域网访问请确认 .env 的 PUBLIC_ORIGIN 并放行端口: firewall-cmd --add-port=${APP_PORT}/tcp --permanent && firewall-cmd --reload"
    exit 0
  fi
  sleep 3
done
err "服务未在 180 秒内就绪。查看日志: $COMPOSE logs teable"
