# Loki 3.1.1 GCS存储速率优化部署配置

这个配置专门针对OpenTelemetry遇到的速率限制和队列爆掉问题进行了优化，使用Google Cloud Storage (GCS) 作为对象存储。

## 🚀 快速部署

### 前置条件
1. 确保有一个GCS存储桶：`loki_44084750`
2. GKE集群（启用Workload Identity）
3. 适当的GCP权限（创建服务账号、IAM绑定）

### 部署步骤
```bash
# 1. 设置环境变量
export PROJECT_ID=your-gcp-project-id
export CLUSTER_NAME=your-gke-cluster-name
export CLUSTER_ZONE=your-cluster-zone
export GSA_NAME=loki-storage  # 可选，默认为loki-storage

# 2. 设置Workload Identity
./setup-workload-identity.sh

# 3. 验证配置
./verify-loki-config.sh

# 4. 执行部署脚本
./deploy-loki.sh
```

## 📁 文件说明

- `loki-namespace.yaml` - grafana-stack namespace定义
- `loki-configmap.yaml` - Loki主配置和运行时配置
- `loki-deployment.yaml` - Loki部署、服务配置（使用Workload Identity）
- `loki-serviceaccount.yaml` - Kubernetes ServiceAccount（Workload Identity）
- `setup-workload-identity.sh` - Workload Identity自动化设置脚本
- `loki-hpa.yaml` - 水平Pod自动伸缩和Pod中断预算
- `loki-servicemonitor.yaml` - Prometheus监控配置
- `deploy-loki.sh` - 自动化部署脚本

## 🔧 主要优化配置

### 速率限制优化
- **摄取速率**: 50MB/s（突发100MB/s）
- **最大流数**: 500,000个全局流
- **查询并发**: 32个并行查询
- **消息大小**: 100MB gRPC消息限制

### 性能优化
- **Chunk配置**: 优化块大小和刷新频率
- **并发刷新**: 32个并发刷新操作
- **WAL启用**: 防止数据丢失
- **内存限制器**: 256MB限制防止OOM

### 自动伸缩
- **最小副本**: 2个（高可用）
- **最大副本**: 8个（应对突发）
- **扩容策略**: 积极扩容，保守缩容
- **监控指标**: CPU 70%，内存 80%

### 存储配置
- **对象存储**: Google Cloud Storage (GCS)
- **存储桶**: `loki_44084750`
- **索引存储**: TSDB (本地缓存)
- **本地存储**: 10GB缓存 + 10GB WAL

### 资源配置
- **CPU**: 请求1核，限制2核
- **内存**: 请求2GB，限制4GB
- **本地存储**: 10GB缓存，10GB WAL（主要数据存储在GCS）

## 📊 监控指标

部署包含ServiceMonitor配置，监控以下关键指标：

- 摄取速率 (`loki_distributor_received_samples_total`)
- 错误率 (`loki_*_errors_total`)
- 队列大小 (`loki_*_queue_*`)
- 延迟指标 (`loki_*_duration_seconds`)

## 🔍 故障排查

### 检查Loki状态
```bash
kubectl get pods -n grafana-stack -l app=loki
kubectl logs -n grafana-stack -l app=loki
```

### 查看HPA状态
```bash
kubectl get hpa -n grafana-stack
kubectl describe hpa loki-hpa -n grafana-stack
```

### 检查配置
```bash
kubectl get configmap loki-config -n grafana-stack -o yaml
```

### 端口转发测试
```bash
# HTTP端点
kubectl port-forward -n grafana-stack svc/loki 3100:3100

# GRPC端点  
kubectl port-forward -n grafana-stack svc/loki 9095:9095
```

## ⚙️ 根据负载调整

### 如果仍然遇到速率限制：

1. **增加摄取速率**:
   ```yaml
   ingestion_rate_mb: 100  # 增加到100MB/s
   ingestion_burst_size_mb: 200  # 增加突发到200MB/s
   ```

2. **增加副本数**:
   ```yaml
   replicas: 4  # 部署中增加初始副本
   maxReplicas: 12  # HPA中增加最大副本
   ```

3. **增加资源**:
   ```yaml
   resources:
     limits:
       cpu: 4000m
       memory: 8Gi
   ```

### 如果资源使用过高：

1. **减少摄取速率**
2. **启用压缩**: 
   ```yaml
   compress_responses: true
   ```
3. **调整chunk参数**:
   ```yaml
   chunk_idle_period: 5m  # 增加空闲时间
   ```

## 🔗 与OpenTelemetry集成

确保您的OpenTelemetry Collector配置中指向正确的Loki端点：

```yaml
exporters:
  loki:
    endpoint: http://loki.grafana-stack.svc.cluster.local:3100/loki/api/v1/push
```

## 🏷️ 标签策略

为避免高基数问题，建议使用有限的标签集合：
- `namespace`
- `pod`  
- `container`
- `level` (info, warn, error)

避免使用高基数标签如timestamp、request_id等。 