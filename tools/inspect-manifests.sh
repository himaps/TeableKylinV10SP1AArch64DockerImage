#!/bin/bash
# Inspect manifests of teable/teable-community on the Aliyun mirror.
# Usage: bash tools/inspect-manifests.sh tag1 tag2 ...
REGISTRY="registry.cn-shenzhen.aliyuncs.com"
REPO="teable/teable-community"
AUTH="https://dockerauth.cn-hangzhou.aliyuncs.com/auth?service=registry.aliyuncs.com:cn-shenzhen:26842"

TOKEN=$(curl -sS --max-time 20 "$AUTH&scope=repository:$REPO:pull" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
if [ -z "$TOKEN" ]; then echo "failed to get token"; exit 1; fi

WORK=$(mktemp -d)

for tag in "$@"; do
  echo "=== $tag ==="
  for MT in "application/vnd.docker.distribution.manifest.list.v2+json" "application/vnd.oci.image.index.v1+json"; do
    HDRS=$(curl -sS --max-time 20 -D - -o "$WORK/m.json" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Accept: $MT, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json" \
      "https://$REGISTRY/v2/$REPO/manifests/$tag")
    CT=$(echo "$HDRS" | grep -i '^content-type:' | tr -d '\r' | head -1)
    DG=$(echo "$HDRS" | grep -i '^docker-content-digest:' | tr -d '\r' | head -1)
    if echo "$CT" | grep -qE "list|index"; then
      echo "  manifest LIST ($CT) $DG"
      MFILE="$WORK/m.json" python -c "
import json, os
m = json.load(open(os.environ['MFILE']))
for mi in m.get('manifests', []):
    p = mi.get('platform', {})
    print('   ->', p.get('os'), p.get('architecture'), p.get('variant', ''), mi['digest'][:27])
"
      break
    elif echo "$CT" | grep -qE "manifest"; then
      echo "  SINGLE manifest ($CT) $DG"
      break
    fi
  done
done
