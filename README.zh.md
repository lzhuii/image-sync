# Image Sync

将 Docker Hub / GCR / GHCR / Quay.io 等仓库的镜像同步到阿里云容器镜像服务（ACR），解决大陆访问外部 registry 慢或不稳定的问题。

**语言：** [English](README.md) · [简体中文](README.zh.md)

---

## 项目简介

`images.txt` 是唯一的用户配置。每次 push 到 `master` 分支都会触发 GitHub Actions 工作流，使用 `skopeo` 把清单里的镜像同步到你的 ACR 实例。基于 digest 比对，未变化的镜像会被跳过。

## 解决的问题

在大陆环境访问 Docker Hub / GCR / GHCR / Quay.io 常见问题：

- **超时**：Kubernetes 和 Helm 拉取镜像经常超时
- **吞吐量不稳定**：同一个镜像，今天几秒，明天几分钟
- **区域封锁**：部分 registry 完全无法访问

CI/CD 流程通常依赖 `ghcr.io/*` 和 `quay.io/*` 的镜像。一旦无法访问，整个流水线就会中断。

## 设计决策

**为什么用 skopeo 而不是 Docker。**
`skopeo` 是一个轻量 CLI（约 50 MB），无需守护进程，支持所有主要 registry 协议，非常适合 CI/CD 镜像同步。

**为什么基于 digest 同步。**
每个镜像都有不可变的 digest（SHA256）。比对源和目标 digest 就能判断镜像是否变化。同步是幂等的，不会浪费带宽。

**为什么用 `skopeo login` 处理凭据。**
目标端 ACR 和源端 Docker Hub（可选）的凭据都由 workflow 通过 `skopeo login` 注入，写到默认 authfile（`~/.config/containers/auth.json`）。`sync.sh` 本身不感知认证，只调用 `skopeo copy`，让 skopeo 自动读取凭据。

**为什么 MVP 不重试。**
加入重试（指数退避、`--retry-times`）会提升健壮性，但也会增加复杂度。MVP 保持脚本精简。需要时可以在后续迭代加入，当前结构支持扩展。

**为什么 push 触发而不是定时。**
公开仓库的 GitHub Actions 分钟数无限免费；定时运行会无谓消耗额度。只有修改了 `images.txt` 才需要拉取新镜像，这是同步的唯一信号。

**为什么保持 `images.txt` 格式不变。**
`namespace|source` 格式简单直观，改动会让现有用户无法升级，收益不明显。

## 快速开始

### 1. Fork 并配置

Fork 本仓库，然后在 **Settings → Secrets and variables → Actions** 中添加必要密钥。

### 2. 编辑 `images.txt`

添加条目，格式为 `命名空间|源镜像`：

```
cn-infra|nginx                          # Docker Hub → registry/cn-infra/nginx
cn-infra|quay.io/jetstack/cert-manager  # Quay.io   → registry/cn-infra/cert-manager
cn-infra|gcr.io/k8s-minikube/kicbase    # GCR       → registry/cn-infra/kicbase
```

`#` 开头为注释（整行或 `|` 之后的行内注释）。空行忽略。

### 3. 推送到 `master`

```bash
git add images.txt && git commit -m "Add images" && git push
```

推送到 `master` 后，GitHub Actions 自动执行同步。

### 4. 本地运行（可选）

```bash
skopeo login registry.cn-beijing.aliyuncs.com -u <user> -p <password>
bash sync.sh
```

## GitHub Secrets

| Secret | 必填 | 说明 |
|---|---|---|
| `ACR_USERNAME` | **是** | 阿里云 ACR 用户名（AccessKey ID） |
| `ACR_PASSWORD` | **是** | 阿里云 ACR 密码（AccessKey Secret） |
| `DOCKERHUB_USERNAME` | 否 | Docker Hub 用户名 |
| `DOCKERHUB_TOKEN` | 否 | Docker Hub 访问令牌 |

若同时设置了 `DOCKERHUB_USERNAME` 和 `DOCKERHUB_TOKEN`，workflow 会执行 `skopeo login docker.io`，以认证用户身份拉取（速率上限：200 次/6 小时）。否则匿名拉取（速率上限：100 次/6 小时/IP）。GHCR、GCR、Quay.io 始终匿名拉取。

## `images.txt` 格式

一行一个，用 `|` 分隔。命名空间和源镜像都必须非空：

```
<namespace>|<source_image>
```

- `<namespace>`：非空字符串，对应目标仓库的子目录。ACR 个人版**硬上限 3 个命名空间**/实例。每次同步前 `bash sync.sh validate` 会检查此限制。
- `<source_image>`：Docker 引用格式，如 `nginx`、`apache/kafka`、`quay.io/jetstack/cert-manager`、`gcr.io/k8s-minikube/kicbase:v0.0.50`。目标镜像名取源镜像的 basename：`quay.io/jetstack/cert-manager` → `<registry>/<namespace>/cert-manager`。

规则：

- `#` 开头为注释，`sync.sh` 会通过 `awk` 剥离行内注释。
- 空行和字段不足 2 个的行被静默忽略。
- 管道符周围的空白自动去除。
- 重复条目会被 `bash sync.sh validate` 拒绝（非零退出，workflow 失败）。
- 命名空间超过 3 个会被 `bash sync.sh validate` 拒绝。

## 环境变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `REGISTRY` | `registry.cn-beijing.aliyuncs.com` | 目标仓库地址 |
| `CONCURRENCY` | `4` | 同步并发数 |
| `MAX_NAMESPACES` | `3` | 命名空间上限（仅校验用） |

`REGISTRY` 默认为北京 ACR 地址。部署到其他区域前需要覆盖（如 `registry.cn-hangzhou.aliyuncs.com`）。

## 本地运行

```bash
# 1. 安装 skopeo（必需）
sudo apt-get install -y skopeo    # Debian/Ubuntu

# 2. 认证到 ACR
skopeo login registry.cn-beijing.aliyuncs.com -u <user> -p <password>

# 3. （可选）认证到 Docker Hub 以使用认证拉取
skopeo login docker.io -u <username> -p <token>

# 4. 运行
bash sync.sh

# 5. 或者仅校验（不联网）
bash sync.sh validate
```

## validate 子命令

`bash sync.sh validate` 对 `images.txt` 进行离线校验，**不联网、不调用 skopeo**。检查项：

- 缺少 `|` 分隔符
- 命名空间或源镜像为空
- 重复条目
- 命名空间数超过 3（或 `$MAX_NAMESPACES`）

工作流会在第一步执行 `bash sync.sh validate`。任何校验错误都会在工作流做任何网络调用前让工作流失败。

## GitHub Actions 免费额度

公开仓库在标准 GitHub-hosted runner 上**分钟数无限免费**。缓存和 artifact 存储独立计费：

| 项目 | 公开仓库（Free 计划） | 私有仓库（Free 计划） |
|---|---|---|
| 标准 runner 分钟数 | 无限（免费） | 2,000 / 月 |
| Artifact 存储 | 500 MB（与 GitHub Packages 共享） | 500 MB |
| Cache 存储 | 10 GB / 仓库 | 10 GB / 仓库 |
| 单 job 超时 | 6 小时 | 6 小时 |
| 单 workflow 超时 | 35 小时 | 35 小时 |

来源：[GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)

本仓库不用 artifact 或 cache（skopeo 直接从源 registry 拉到 ACR），所以完全零成本。**保持仓库公开即可。**

**重要**：如果仓库转为私有，2,000 分钟大约覆盖每天 10 次同步（假设每次 10 分钟）。高频使用请保持仓库公开。

## 配额与限制

### 阿里云 ACR 个人版

默认目标（`registry.cn-beijing.aliyuncs.com`）是 **ACR 个人版**。官方 [规格说明](https://help.aliyun.com/zh/acr/product-overview/what-is-container-registry)：

| 项目 | 数值 |
|---|---|
| 命名空间 | 3（硬上限） |
| 公开仓库 | 300 |
| 并发构建 | 1 |
| 拉取 QPS | **无保障** |
| SLA | 无 |
| VPC 访问控制 | 无 |
| 版本不可变 | 无 |
| 自动清理 | 无 |
| 网络访问控制 / 审计 | 无 |

**官方警告**：ACR 个人版"无 SLA 承诺及 SLA 受损赔偿且有使用限制，请勿在生产业务中使用"。

补充说明：**2024-09-04 起新创建**的实例不再支持 `aliyun-acr-credential-helper` 免密拉取组件，K8s 部署必须使用传统的 `imagePullSecret`。

### Docker Hub 拉取速率限制

Docker Hub [速率限制](https://docs.docker.com/docker-hub/download-rate-limit/) 按滚动 6 小时窗口执行：

| 用户类型 | 拉取次数 / 6 小时 |
|---|---|
| 匿名（按 IP） | 100 |
| 个人（认证） | 200 |
| 团队 / 专业 / 商业 | 无限 |

配置 `DOCKERHUB_USERNAME` 和 `DOCKERHUB_TOKEN` secrets 可将限额从 100 提升到 200。

## 故障排查

**Docker Hub 返回 `429 Too Many Requests`。**
匿名速率限制已用尽。配置 `DOCKERHUB_USERNAME` 和 `DOCKERHUB_TOKEN` secrets，或等 6 小时窗口重置后重试。

**推送 ACR 时 `401 Unauthorized`。**
`ACR_USERNAME` / `ACR_PASSWORD` 缺失、过期或无推送权限。确认 AccessKey 对目标命名空间有写权限。

**源镜像 `image not found`。**
源 tag 不存在或无法访问。先用浏览器确认引用格式。

**命名空间超限（校验失败）。**
清单使用了超过 3 个不同的命名空间。合并到更少的命名空间，或升级到 ACR 企业版。

**重复条目（校验失败）。**
`images.txt` 中有两行指向同一个 `namespace|source`。删除重复行。

## 生产使用建议

- **生产环境请使用 ACR 企业版，而非个人版。** 企业版提供 VPC 访问控制、SLA、安全扫描、审计日志和更高配额。本仓库默认 `REGISTRY` 指向个人版，使用企业版请覆盖。
- **保持仓库公开。** 公开仓库的 GitHub Actions 分钟数无限免费；私有仓库每月 2,000 分钟封顶。
- **重要镜像请使用 Docker Hub 认证拉取。** 匿名拉取 100 次/6 小时限制容易被同 IP 上其他用户的 CI 活动挤占。
- **控制 `images.txt` 规模。** 每次 push 会重新同步清单里的每一条镜像。清单里几百个镜像意味着每次 push 拉几百个镜像。规模大时请拆分。
- **关注 ACR 存储。** 个人版无自动清理，旧 tag 会随时间堆积。

## 许可证

MIT
