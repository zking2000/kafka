# Mimir GKE Demo 环境

这是一个在Google Kubernetes Engine (GKE)上部署Mimir的demo环境，使用Google Cloud Storage (GCS)作为后端存储，并配置了24小时数据保留策略。

## 架构概述

- **Mimir**: 主要的指标存储和查询服务
- **GCS**: 后端对象存储，用于长期存储指标数据
- **Memcached**: 缓存服务，提高查询性能
- **Prometheus**: 指标收集器，将数据推送到Mimir
- **Grafana**: 可视化仪表板

## 前置要求

1. **GKE集群**: 已创建并运行的GKE集群
2. **工具安装**:
   - `kubectl` - Kubernetes命令行工具
   - `gcloud` - Google Cloud SDK

3. **权限**:
   - 对GCP项目的编辑权限
   - 对GKE集群的管理权限
   - 创建IAM服务账号的权限

## 快速部署

### 1. 设置环境变量

```bash
export PROJECT_ID="your-gcp-project-id"
export CLUSTER_NAME="your-gke-cluster-name"
export ZONE="us-central1-a"
export BUCKET_NAME="your-unique-bucket-name"
```

### 2. 运行部署脚本

```bash
chmod +x deploy-gke.sh
./deploy-gke.sh
```

脚本将自动执行以下操作：
- 创建GCS bucket
- 创建Google服务账号并配置权限
- 设置Workload Identity
- 部署所有Kubernetes资源
- 等待服务启动

### 3. 访问服务

部署完成后，您可以通过以下方式访问服务：

- **Grafana**: 通过LoadBalancer IP访问，默认用户名/密码: `admin/admin`
- **Mimir API**: `kubectl port-forward -n mimir-demo svc/mimir 8080:8080`
- **Prometheus**: `kubectl port-forward -n mimir-demo svc/prometheus 9090:9090`

## 手动部署步骤

如果您prefer手动部署，请按以下顺序应用Kubernetes资源：

```bash
# 1. 创建命名空间
kubectl apply -f k8s-namespace.yaml

# 2. 创建服务账号和RBAC
kubectl apply -f k8s-serviceaccount.yaml

# 3. 创建配置映射
kubectl apply -f k8s-configmap.yaml

# 4. 部署Memcached
kubectl apply -f k8s-memcached.yaml

# 5. 部署Mimir
kubectl apply -f k8s-mimir.yaml

# 6. 部署Prometheus
kubectl apply -f k8s-prometheus.yaml

# 7. 部署Grafana
kubectl apply -f k8s-grafana.yaml
```

## 配置说明

### 数据保留策略

配置了24小时数据保留策略：
- `retention_period: 24h` - TSDB块保留时间
- `compactor_blocks_retention_period: 24h` - 压缩器删除旧块的时间
- `deletion_delay: 1h` - 删除延迟，防止误删
- `cleanup_interval: 15m` - 清理检查间隔

### GCS存储配置

- 使用GCS作为后端存储
- 支持Workload Identity，无需管理密钥文件
- 自动处理数据分片和复制

### 资源限制

为demo环境设置了适当的资源限制：
- Mimir: 512Mi-2Gi内存, 250m-1000m CPU
- Memcached: 64Mi-128Mi内存, 50m-100m CPU
- Prometheus: 256Mi-512Mi内存, 100m-500m CPU
- Grafana: 128Mi-256Mi内存, 100m-200m CPU

## 监控和故障排除

### 查看Pod状态
```bash
kubectl get pods -n mimir-demo
```

### 查看Mimir日志
```bash
kubectl logs -n mimir-demo -l app=mimir -f
```

### 查看服务状态
```bash
kubectl get svc -n mimir-demo
```

### 进入Mimir容器进行调试
```bash
kubectl exec -it -n mimir-demo deployment/mimir -- /bin/sh
```

## 数据验证

1. **检查Prometheus是否正在推送数据**:
   - 访问Prometheus UI: `kubectl port-forward -n mimir-demo svc/prometheus 9090:9090`
   - 查看 Status > Targets 确认target状态

2. **检查Mimir是否接收数据**:
   - 访问Mimir API: `kubectl port-forward -n mimir-demo svc/mimir 8080:8080`
   - 访问 `http://localhost:8080/api/v1/query?query=up`

3. **在Grafana中查询数据**:
   - 登录Grafana
   - 创建新的dashboard
   - 使用PromQL查询: `up`, `prometheus_build_info`, 等

## 清理资源

使用提供的清理脚本删除所有资源：

```bash
chmod +x cleanup.sh
./cleanup.sh
```

## 生产环境注意事项

这是一个demo环境，在生产环境中需要考虑：

1. **高可用性**: 增加副本数量，配置多个可用区
2. **安全性**: 配置网络策略，启用TLS加密
3. **监控**: 添加更多监控指标和告警规则
4. **备份**: 配置数据备份策略
5. **性能**: 根据负载调整资源配置和存储类型
6. **成本优化**: 使用生命周期管理策略管理GCS成本

## 故障排除

### 常见问题

1. **Pod无法启动**:
   - 检查资源配额: `kubectl describe quota -n mimir-demo`
   - 检查镜像拉取: `kubectl describe pod <pod-name> -n mimir-demo`

2. **GCS访问权限问题**:
   - 验证Workload Identity配置
   - 检查服务账号权限

3. **网络连接问题**:
   - 检查Service配置
   - 验证防火墙规则

### 支持

如有问题，请检查：
- [Mimir官方文档](https://grafana.com/docs/mimir/)
- [GKE文档](https://cloud.google.com/kubernetes-engine/docs)
- Kubernetes事件: `kubectl get events -n mimir-demo --sort-by='.lastTimestamp'` 