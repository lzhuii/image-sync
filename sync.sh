#!/usr/bin/env bash
# 同步 images.txt 中的镜像到目标仓库
# 用法：
#   bash sync.sh            执行同步
#   bash sync.sh validate   仅校验 images.txt，不联网
set -euo pipefail

REGISTRY="${REGISTRY:-registry.cn-beijing.aliyuncs.com}"
REGISTRY="${REGISTRY%/}"

usage() {
	cat <<EOF
用法：bash sync.sh [validate]

参数：
  validate  仅校验 images.txt 格式，不联网、不同步

环境变量：
  REGISTRY        目标仓库地址（默认 ${REGISTRY}）

源端凭据通过 skopeo 默认 authfile 读取，由调用方（如 GitHub Actions）
预先执行 skopeo login 完成。本脚本不处理认证。
EOF
}

# 解析 images.txt，输出 "namespace|source_image" 格式
# 跳过空行、注释、字段不足的行；去除首尾空白和行内注释
parse_images() {
	local input="${1:-images.txt}"
	awk -F'|' '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        {
            sub(/[[:space:]]*#.*/, "")
            if (NF < 2) next
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
            if ($1 != "" && $2 != "") print $1 "|" $2
        }
    ' "$input"
}

validate_manifest() {
	local input="${1:-images.txt}"

	awk -F'|' '
        BEGIN { errors = 0; count = 0 }
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        {
            sub(/[[:space:]]*#.*/, "")
            if (NF < 2) {
                printf "错误：行 %d 缺少 \"|\" 分隔符\n", NR > "/dev/stderr"
                errors++
                next
            }
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
            if ($1 == "") {
                printf "错误：行 %d 命名空间为空\n", NR > "/dev/stderr"
                errors++
                next
            }
            if ($2 == "") {
                printf "错误：行 %d 源镜像为空\n", NR > "/dev/stderr"
                errors++
                next
            }
            key = $1 "|" $2
            if (key in seen) {
                printf "错误：行 %d 重复条目 %s\n", NR, key > "/dev/stderr"
                errors++
            } else {
                seen[key] = 1
                namespaces[$1] = 1
                count++
            }
        }
        END {
            ns_count = 0
            for (ns in namespaces) ns_count++
            if (errors > 0) {
                printf "校验失败：%d 个错误\n", errors > "/dev/stderr"
                exit 1
            }
            printf "校验通过：%d 条镜像，%d 个命名空间\n", count, ns_count > "/dev/stderr"
        }
    ' "$input"
}

sync_one() {
	local namespace="$1" source="$2"
	local dest="${REGISTRY}/${namespace}/${source##*/}"
	local src_digest dest_digest

	src_digest=$(skopeo inspect --format '{{.Digest}}' "docker://$source") || {
		echo "✗ 失败 $source → $dest（源端拉取失败）"
		return 1
	}

	dest_digest=$(skopeo inspect --format '{{.Digest}}' "docker://$dest" 2>/dev/null) || true
	if [ -n "$dest_digest" ] && [ "$src_digest" = "$dest_digest" ]; then
		echo "○ 跳过 $source → $dest（digest 一致 ${src_digest:0:19}...）"
		return 0
	fi

	if skopeo copy -a "docker://$source" "docker://$dest"; then
		echo "✓ 同步 $source → $dest（多架构）"
		return 0
	fi

	echo "！ 多架构失败，回退到 --override-arch amd64"
	if ! skopeo copy --override-arch amd64 --override-os linux "docker://$source" "docker://$dest"; then
		echo "✗ 失败 $source → $dest（复制失败）"
		return 1
	fi
	echo "✓ 同步 $source → $dest（单架构 amd64）"
}

main() {
	local failures=0 namespace source

	while IFS='|' read -r namespace source; do
		sync_one "$namespace" "$source" || failures=$((failures + 1))
	done < <(parse_images)

	if [ "$failures" -gt 0 ]; then
		echo "" >&2
		echo "汇总：失败 $failures 个镜像" >&2
		exit 1
	fi
}

case "${1:-}" in
validate) validate_manifest "${2:-images.txt}" ;;
help | -h | --help) usage ;;
"") main ;;
*)
	echo "未知参数：$1" >&2
	usage
	exit 2
	;;
esac
