# Image Sync

🚀 **一键同步 Docker 镜像到阿里云容器镜像服务**

这个工具通过自动化流程将指定的 Docker 镜像从各种源（如 Docker Hub、GCR 等）同步到你的阿里云容器镜像服务。支持增量同步，只复制有更新的镜像，节省时间和带宽。

## ✨ 特性

- 🔄 **智能同步**：检查镜像摘要，只同步有变化的镜像
- 📦 **批量处理**：支持多个镜像和命名空间
- 🛡️ **高效可靠**：使用 `skopeo` 进行安全、快速的镜像传输
- 📝 **简单配置**：只需编辑 `images.txt` 文件添加镜像列表
- 🤖 **自动化触发**：Push 代码自动同步，无需手动操作

## 🚀 快速开始

### 1. 添加镜像

编辑 `images.txt` 文件，添加需要同步的镜像。每行格式：`命名空间|源镜像`

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

## 📋 镜像列表

当前支持的镜像包括：

- **基础语言环境**：Python, Minikube KIC
- **基础设施**：PostgreSQL, MySQL, Redis, Nginx, MinIO, Flink Operator, Cert Manager, Kubernetes Dashboard
- **应用工具**：PalServer 等

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！请在 `images.txt` 中添加新镜像或改进脚本。

## 📄 许可证

MIT License
