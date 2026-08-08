#!/bin/bash
# 将 images.txt 中列出的镜像同步到目标仓库（默认阿里云 ACR）
#
# 用法：
#   bash sync.sh
#   REGISTRY=registry.cn-beijing.aliyuncs.com CONCURRENCY=8 RETRIES=3 bash sync.sh
#
# 可配置环境变量：
#   REGISTRY      目标仓库地址（默认 registry.cn-beijing.aliyuncs.com）
#   CONCURRENCY   同时同步的镜像数量（默认 4）
#   RETRIES       单个镜像失败后的重试次数（默认 3）
#   LIST_FILE     镜像列表文件（默认 images.txt，也可作为第一个参数传入）

set -uo pipefail

REGISTRY="${REGISTRY:-registry.cn-beijing.aliyuncs.com}"
REGISTRY="${REGISTRY%/}"
CONCURRENCY="${CONCURRENCY:-4}"
RETRIES="${RETRIES:-3}"
LIST_FILE="${1:-${LIST_FILE:-images.txt}}"

if ! command -v skopeo >/dev/null 2>&1; then
    echo "错误：未找到 skopeo，请先安装。" >&2
    exit 1
fi

if [ ! -r "$LIST_FILE" ]; then
    echo "错误：找不到镜像列表文件 $LIST_FILE" >&2
    exit 1
fi

sync_one() {
    local namespace="$1" src="$2"
    local dst src_digest dst_digest attempt

    dst="$REGISTRY/$namespace/${src##*/}"

    for attempt in $(seq 1 "$RETRIES"); do
        src_digest=$(skopeo inspect --format '{{.Digest}}' "docker://$src" 2>/dev/null) || {
            echo "[$(date -u '+%F %TZ')] 获取源镜像摘要失败：$src（第 ${attempt}/${RETRIES} 次）" >&2
            sleep 3
            continue
        }

        dst_digest=$(skopeo inspect --format '{{.Digest}}' "docker://$dst" 2>/dev/null || true)
        if [ -n "$dst_digest" ] && [ "$src_digest" = "$dst_digest" ]; then
            echo "[$(date -u '+%F %TZ')] 已是最新，跳过：$dst"
            return 0
        fi

        echo "[$(date -u '+%F %TZ')] 同步：$src -> $dst"
        if skopeo copy --all "docker://$src" "docker://$dst"; then
            echo "[$(date -u '+%F %TZ')] 完成：$dst"
            return 0
        fi
        echo "[$(date -u '+%F %TZ')] 同步失败，准备重试：$src（第 ${attempt}/${RETRIES} 次）" >&2
        sleep 3
    done

    echo "[$(date -u '+%F %TZ')] 同步失败：$src" >&2
    return 1
}

export -f sync_one
export REGISTRY RETRIES

# 解析镜像清单：忽略空行与注释行，支持行内注释，去除首尾空白
awk -F'|' '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    {
        line = $0
        sub(/[[:space:]]*#.*/, "", line)
        if (split(line, f, "|") < 2) next
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", f[1])
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", f[2])
        if (f[1] != "" && f[2] != "") print f[1] "|" f[2]
    }
' "$LIST_FILE" |
    xargs -P "$CONCURRENCY" -I{} bash -c 'sync_one "${1%%|*}" "${1#*|}"' _ {}

rc=$?
if [ "$rc" -ne 0 ]; then
    echo "存在同步失败的镜像，请检查上方日志。" >&2
    exit 1
fi

echo "全部镜像同步完成。"
