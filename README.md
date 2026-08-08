# Image Sync

🚀 **一键同步 Docker 镜像到阿里云容器镜像服务**

这个工具通过自动化流程将指定的 Docker 镜像从各种源（如 Docker Hub、GCR 等）同步到你的阿里云容器镜像服务。支持增量同步，只复制有更新的镜像，节省时间和带宽。

## ✨ 特性

- 🔄 **智能同步**：检查镜像摘要，只同步有变化的镜像
- 📦 **批量处理**：支持多个镜像和命名空间
- 🛡️ **高效可靠**：使用 `skopeo` 传输镜像，支持并行同步与失败自动重试
- 📝 **简单配置**：只需编辑 `images.txt` 文件添加镜像列表
- 🤖 **自动化触发**：Push 代码、手动触发或每日定时自动同步

## 🚀 快速开始

### 1. 添加镜像

编辑 `images.txt` 文件，添加需要同步的镜像。每行格式：`命名空间|源镜像`，支持行内注释：

例如：

```
my-app|nginx:latest
my-db|postgres:13
```

### 2. 提交并推送

```bash
git add images.txt
git commit -m "Add new images"
git push
```

推送后，自动化流程会自动触发同步所有镜像！

### 3. 手动触发（可选）

在 GitHub 仓库的 **Actions** 页面选择 **Sync Container Images to ACR**，点击 **Run workflow** 即可手动执行一次同步。

## ⚙️ 配置

脚本支持通过环境变量调整同步行为：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `REGISTRY` | `registry.cn-beijing.aliyuncs.com` | 目标仓库地址 |
| `CONCURRENCY` | `4` | 同时同步的镜像数量 |
| `RETRIES` | `3` | 单个镜像失败后的重试次数 |

本地运行示例：

```bash
REGISTRY=registry.cn-beijing.aliyuncs.com CONCURRENCY=8 bash sync.sh
```

## 📋 镜像列表

当前支持的镜像包括：

- **基础语言环境**：Python, Minikube KIC
- **基础设施**：PostgreSQL, MySQL, Redis, Nginx, MinIO, Flink Operator, Cert Manager, Kubernetes Dashboard
- **应用工具**：PalServer 等

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！请在 `images.txt` 中添加新镜像或改进脚本。

## 📄 许可证

MIT License
