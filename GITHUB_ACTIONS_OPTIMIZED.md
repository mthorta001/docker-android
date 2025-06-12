# GitHub Actions 优化版本构建指南

本文档描述如何使用 GitHub Actions 来构建优化版本的 Docker Android 镜像。

## 🚀 快速开始

### 1. 准备 Docker Hub 凭据

在您的 GitHub 仓库中设置以下 Secrets：

- `DOCKER_USERNAME`: 您的 Docker Hub 用户名
- `DOCKER_PASSWORD`: 您的 Docker Hub 密码或 Access Token

设置路径：`Settings` → `Secrets and variables` → `Actions` → `New repository secret`

### 2. 运行优化构建

1. 转到 GitHub 仓库的 `Actions` 页面
2. 选择 `Android emulator (Optimized)` workflow
3. 点击 `Run workflow`
4. 填写参数：
   - **Image tag version**: 镜像标签版本 (必填)
   - **Build type**: 构建类型 (可选)
     - `standard`: 标准构建
     - `no-cache`: 无缓存构建
     - `squash`: 压缩层构建
   - **Enable image compression**: 启用镜像压缩 (可选)

## 📋 构建选项详解

### 构建类型

#### Standard (标准)
- 使用 Docker 缓存加速构建
- 推荐用于日常开发和测试

#### No-cache (无缓存)
- 从头构建，忽略所有缓存
- 确保最新的依赖和组件
- 构建时间较长，但结果更可靠

#### Squash (压缩层)
- 将多个层压缩为单个层
- 进一步减小镜像大小
- 需要 Docker 实验性功能支持

### 镜像压缩
- 启用构建时压缩
- 减少网络传输时间
- 轻微增加构建时间

## 🔧 构建过程

优化版本的构建过程包括：

1. **环境准备**
   - 清理不必要的软件包
   - 释放磁盘空间
   - 设置 Docker Buildx

2. **运行测试**
   - 执行单元测试
   - 验证代码质量

3. **构建优化镜像**
   - 使用优化的 Dockerfile
   - 应用构建选项
   - 合并层以减小大小

4. **推送到 Docker Hub**
   - 推送主标签
   - 推送优化标签
   - 推送版本标签

5. **验证测试**
   - 启动容器测试
   - 验证基本功能
   - 生成镜像大小报告

## 📊 预期效果

### 镜像大小优化
- **原始镜像**: ~8.8GB
- **优化后镜像**: ~5-7GB
- **减少比例**: 20-40%

### 构建时间
- **标准构建**: 45-75 分钟
- **无缓存构建**: 60-90 分钟
- **GitHub Actions限制**: 最大 6 小时

### 支持的 Android 版本
- Android 12.0
- Android 14.0  
- Android 15.0
- Android 16.0

## 🏗️ 与标准版本的区别

| 特性 | 标准版本 | 优化版本 |
|------|----------|----------|
| 镜像大小 | ~8.8GB | ~5-7GB |
| 构建时间 | 60-90分钟 | 45-75分钟 |
| 层数量 | 15+ | 8-10 |
| 缓存清理 | 基础 | 全面 |
| SDK优化 | 无 | 全面 |
| 调试工具 | 包含 | 移除 |

## 📝 生成的镜像标签

对于 Android 12.0，版本标签 v1.21.0，会生成：

- `budtmo/docker-android:emulator_12.0`
- `budtmo/docker-android:emulator_12.0-optimized`  
- `budtmo/docker-android:emulator_12.0-v1.21.0`

## 🔍 故障排除

### 构建失败
1. 检查 Docker Hub 凭据是否正确
2. 确认 Android 版本支持
3. 查看构建日志中的错误信息

### 磁盘空间不足
- GitHub Actions 提供约 14GB 可用空间
- 优化版本会自动清理磁盘空间
- 如果仍然不足，考虑移除更多不必要组件

### 构建超时
- GitHub Actions 有 6 小时限制
- 考虑使用 `squash` 选项减少推送时间
- 检查网络连接是否稳定

## 🎯 最佳实践

1. **版本管理**
   - 使用语义化版本号
   - 为重要版本创建 Git 标签

2. **构建策略**
   - 开发阶段使用标准构建
   - 发布前使用无缓存构建
   - 生产发布使用压缩构建

3. **监控构建**
   - 定期检查构建日志
   - 监控镜像大小变化
   - 验证功能完整性

## 📞 支持

如果遇到问题：

1. 检查本文档的故障排除部分
2. 查看 GitHub Actions 构建日志
3. 参考 `OPTIMIZATION.md` 了解更多优化细节
4. 创建 GitHub Issue 报告问题

---

**注意**: 首次构建可能需要较长时间，后续构建会利用缓存加速。建议在非高峰时间运行大型构建任务。 