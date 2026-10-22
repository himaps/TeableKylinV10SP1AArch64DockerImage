#!/usr/bin/env bash
# 停止并移除 Teable 容器。数据卷默认保留；加 --purge 连数据一起删除。
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
else
  echo "[信息] 容器已停止删除，数据卷已保留(重新 bash install.sh 即恢复)"
  echo "       彻底删除数据: bash $0 --purge"
fi
