# Image Sync

一键将 Docker Hub / GCR / GHCR / Quay.io 等仓库的镜像同步到阿里云 ACR。

## 工作原理

`images.txt` 维护镜像清单 → GitHub Actions 触发 `sync.sh` → `skopeo` 比对 digest，仅同步有变化的镜像。

## 快速开始

### 1. 配置 Secrets

在仓库 **Settings → Secrets** 中添加：

| Secret         | 说明                     |
| -------------- | ------------------------ |
| `ACR_USERNAME` | 阿里云容器镜像服务用户名 |
| `ACR_PASSWORD` | 阿里云容器镜像服务密码   |

### 2. 编辑镜像清单

在 `images.txt` 中添加条目，格式为 `命名空间|源镜像`：

```
cn-infra|nginx                          # Docker Hub → registry/cn-infra/nginx
cn-infra|quay.io/jetstack/cert-manager  # Quay.io   → registry/cn-infra/cert-manager
cn-infra|gcr.io/k8s-minikube/kicbase    # GCR       → registry/cn-infra/kicbase
```

以 `#` 开头的行为注释，空行自动忽略。

### 3. 推送触发同步

```bash
git add images.txt && git commit -m "Add images" && git push
```

推送到 `master` 分支后，GitHub Actions 自动执行同步。

## 配置

通过环境变量调整行为：

| 变量          | 默认值                             | 说明         |
| ------------- | ---------------------------------- | ------------ |
| `REGISTRY`    | `registry.cn-beijing.aliyuncs.com` | 目标仓库地址 |
| `CONCURRENCY` | `4`                                | 同步并发数   |

本地运行：

```bash
skopeo login registry.cn-beijing.aliyuncs.com -u <user> -p <password>
REGISTRY=registry.cn-beijing.aliyuncs.com CONCURRENCY=8 bash sync.sh
```

## 项目结构

```
.
├── sync.sh                          # 核心同步脚本
├── images.txt                       # 镜像清单
└── .github/workflows/sync.yml       # GitHub Actions 工作流
```

## 依赖

- [skopeo](https://github.com/podman-container-tools/skopeo)

## 许可证

MIT
