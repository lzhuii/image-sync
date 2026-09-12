#!/bin/bash
# 同步 images.txt 中的镜像到目标仓库
# 用法：
#   bash sync.sh            执行同步
#   bash sync.sh validate   仅校验 images.txt，不联网
# shellcheck disable=SC2016  # bash -c 内的参数展开由子 shell 处理，故意保留单引号
set -uo pipefail

REGISTRY="${REGISTRY:-registry.cn-beijing.aliyuncs.com}"
REGISTRY="${REGISTRY%/}"
CONCURRENCY="${CONCURRENCY:-4}"

MAX_NAMESPACES="${MAX_NAMESPACES:-3}"

usage() {
    cat <<EOF
用法：bash sync.sh [validate]

参数：
  validate  仅校验 images.txt 格式，不联网、不同步

环境变量：
  REGISTRY        目标仓库地址（默认 ${REGISTRY}）
  CONCURRENCY     同步并发数（默认 ${CONCURRENCY}）
  MAX_NAMESPACES  最大命名空间数上限（默认 ${MAX_NAMESPACES}，ACR 个人版为 3）

源端凭据通过 skopeo 默认 authfile 读取，由调用方（如 GitHub Actions）
预先执行 skopeo login 完成。本脚本不处理认证。
EOF
}

validate_manifest() {
    local input="${1:-images.txt}"

    awk -v max_ns="$MAX_NAMESPACES" -F'|' '
        BEGIN { errors = 0; total = 0 }
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        {
            sub(/[[:space:]]*#.*/, "")
            n = split($0, parts, "|")
            if (n < 2) {
                printf "行 %d: 缺少 \"|\" 分隔符\n", NR > "/dev/stderr"
                errors++
                next
            }
            ns = parts[1]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", ns)
            src = parts[2]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", src)
            if (ns == "") {
                printf "行 %d: 命名空间为空\n", NR > "/dev/stderr"
                errors++
                next
            }
            if (src == "") {
                printf "行 %d: 源镜像为空\n", NR > "/dev/stderr"
                errors++
                next
            }
            key = ns "|" src
            if (key in entries) {
                printf "行 %d: 重复条目 %s\n", NR, key > "/dev/stderr"
                errors++
            } else {
                entries[key] = 1
                ns_seen[ns] = 1
                total++
            }
        }
        END {
            ns_count = 0
            for (k in ns_seen) ns_count++
            if (ns_count > max_ns) {
                printf "错误：命名空间数 %d 超过上限 %d（ACR 个人版硬上限）\n", ns_count, max_ns > "/dev/stderr"
                errors++
            }
            if (errors > 0) {
                printf "校验失败：%d 个错误\n", errors > "/dev/stderr"
                exit 1
            }
            printf "校验通过：%d 条镜像，%d 个命名空间\n", total, ns_count > "/dev/stderr"
        }
    ' "$input"
}

sync_one() {
    local ns="$1" src="$2"
    local dst="$REGISTRY/$ns/${src##*/}"

    local src_d dst_d stderr_file
    stderr_file=$(mktemp)

    src_d=$(skopeo inspect --format '{{.Digest}}' "docker://$src" 2>"$stderr_file") || {
        echo "✗ 失败 $src → $dst（源端拉取失败）"
        echo "  $(tail -3 "$stderr_file")"
        rm -f "$stderr_file"
        return 1
    }

    dst_d=$(skopeo inspect --format '{{.Digest}}' "docker://$dst" 2>/dev/null) || true
    if [ -n "$dst_d" ] && [ "$src_d" = "$dst_d" ]; then
        echo "＝ 跳过 $src → $dst（digest 一致 ${src_d:0:19}...）"
        rm -f "$stderr_file"
        return 0
    fi

    skopeo copy -a "docker://$src" "docker://$dst" 2>"$stderr_file" || {
        echo "✗ 失败 $src → $dst（复制失败）"
        echo "  $(tail -3 "$stderr_file")"
        rm -f "$stderr_file"
        return 1
    }
    rm -f "$stderr_file"
    echo "✓ 同步 $src → $dst（digest ${src_d:0:19}...）"
}

main() {
    export -f sync_one
    export REGISTRY

    awk -F'|' '/^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        { sub(/[[:space:]]*#.*/, ""); if (split($0, f, "|") < 2) next
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", f[1])
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", f[2])
          if (f[1] != "" && f[2] != "") print f[1] "|" f[2]
        }' images.txt |
        xargs -P "$CONCURRENCY" -I{} bash -c 'sync_one "${1%%|*}" "${1#*|}"' _ {} |
        awk '
            BEGIN { total = 0; ok = 0; skip = 0; fail = 0 }
            /^✓/ { total++; ok++; print }
            /^＝/ { total++; skip++; print }
            /^✗/ { total++; fail++; print }
            END {
                printf "\n══════════════════════════════════\n"
                printf "汇总：同步 %d · 跳过 %d · 失败 %d · 总计 %d\n", ok, skip, fail, total
                if (fail > 0) exit 1
            }
        '
}

case "${1:-}" in
    validate)
        validate_manifest "${2:-images.txt}"
        ;;
    help|-h|--help)
        usage
        ;;
    "")
        main
        ;;
    *)
        echo "未知参数：$1" >&2
        usage
        exit 2
        ;;
esac
