#!/usr/bin/env bash
# 停止并移除 ONLYOFFICE 协同编辑全部容器。数据默认保留；加 --purge 连数据卷一起删除。
# 用法: bash uninstall.sh [--purge]
set -euo pipefail
cd "$(dirname "$0")"

if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
else
  COMPOSE="docker-compose"
fi

$COMPOSE down

if [ "${1:-}" = "--purge" ]; then
  $COMPOSE down -v
  echo "[信息] 容器与数据卷已全部删除"
  echo "       注意: ./data 目录(用户文件/连接器/字体)仍在磁盘上，确认不要可手动删除"
else
  echo "[信息] 容器已停止删除，数据卷与 ./data 已保留(重新 bash install.sh 即恢复)"
  echo "       彻底删除数据: bash $0 --purge"
fi
