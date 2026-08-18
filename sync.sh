#!/bin/bash
# 同步 images.txt 中的镜像到目标仓库
# 用法：bash sync.sh  环境变量：REGISTRY  CONCURRENCY

set -uo pipefail

REGISTRY="${REGISTRY:-registry.cn-beijing.aliyuncs.com}"
REGISTRY="${REGISTRY%/}"
CONCURRENCY="${CONCURRENCY:-4}"

sync_one() {
    local ns="$1" src="$2"
    local dst="$REGISTRY/$ns/${src##*/}"

    src_d=$(skopeo inspect --format '{{.Digest}}' "docker://$src" 2>/dev/null) || return
    dst_d=$(skopeo inspect --format '{{.Digest}}' "docker://$dst" 2>/dev/null || true)
    [ -n "$dst_d" ] && [ "$src_d" = "$dst_d" ] && return

    skopeo copy --all "docker://$src" "docker://$dst" >/dev/null && echo "✓ $dst"
}

export -f sync_one
export REGISTRY

awk -F'|' '/^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    { sub(/[[:space:]]*#.*/, ""); if (split($0, f, "|") < 2) next
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", f[1])
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", f[2])
      if (f[1] != "" && f[2] != "") print f[1] "|" f[2]
    }' images.txt |
    xargs -P "$CONCURRENCY" -I{} bash -c 'sync_one "${1%%|*}" "${1#*|}"' _ {}

echo "完成"
