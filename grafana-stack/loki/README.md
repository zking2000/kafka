# Loki 3.1.1 Demo环境部署

本项目提供在 Kubernetes 集群中部署 **Demo环境** Loki 3.1.1 的完整配置。

## 🎯 Demo环境特性

### 📊 配置概览
- **版本**: Loki 3.1.1
- **模式**: 单体模式 (monolithic)
- **副本数**: 1个Pod
- **认证**: 禁用 (`auth_enabled: false`)
- **存储**: emptyDir (非持久化) + GCS对象存储
- **资源**: 500m CPU, 1GB内存
- **限制**: 20MB/s写入，40MB/s突发

### 🔧 技术配置
- **Schema**: v13 + TSDB
- **WAL**: 启用
- **压缩**: 启用
- **命名空间**: `grafana-stack`
- **GCS存储桶**: `loki_44084750`

## 🚀 快速部署

### 前置条件
```bash
# 确保kubectl已连接到集群
kubectl cluster-info

# 确保有namespace权限
kubectl auth can-i create namespace
```

### 一键部署
```bash
chmod +x deploy-loki-demo.sh
./deploy-loki-demo.sh
```

### 手动部署
```bash
# 1. 创建namespace
kubectl create namespace grafana-stack

# 2. 部署ServiceAccount (Workload Identity)
kubectl apply -f loki-serviceaccount.yaml

# 3. 部署配置
kubectl apply -f loki-configmap-demo.yaml

# 4. 部署Loki
kubectl apply -f loki-deployment-demo.yaml
```

## 📊 验证部署

### 检查Pod状态
```bash
kubectl get pods -l app=loki -n grafana-stack
```

### 检查服务
```bash
kubectl get svc -l app=loki -n grafana-stack
```

### 健康检查
```bash
# 端口转发
kubectl port-forward svc/loki 3100:3100 -n grafana-stack

# 测试接口
curl http://localhost:3100/ready
curl http://localhost:3100/metrics
```

### 查看日志
```bash
kubectl logs -f deployment/loki -n grafana-stack
```

## 📡 使用Demo环境

### 发送测试日志
```bash
# 使用promtail或其他日志收集器发送到:
# http://loki.grafana-stack.svc.cluster.local:3100
```

### Grafana集成
在Grafana中添加Loki数据源：
```
URL: http://loki.grafana-stack.svc.cluster.local:3100
```

### LogQL查询示例
```logql
# 查看所有日志
{job="example"}

# 过滤错误日志
{job="example"} |= "error"

# 时间范围查询
{job="example"}[5m]
```

## 🗑️ 清理环境

### 删除Loki部署
```bash
kubectl delete namespace grafana-stack
```

### 或者单独删除资源
```bash
kubectl delete -f loki-deployment-demo.yaml
kubectl delete -f loki-configmap-demo.yaml
kubectl delete -f loki-serviceaccount.yaml
```

## ⚠️ Demo环境注意事项

1. **非持久化存储**: 使用emptyDir，Pod重启会丢失本地数据
2. **单副本**: 无高可用性，适合测试和开发
3. **无认证**: 任何有集群访问权限的用户都可以访问
4. **资源限制**: 较小的资源配置，不适合高负载
5. **无监控**: 未包含生产级监控和告警

## 🔧 配置定制

### 调整资源限制
编辑 `loki-deployment-demo.yaml`:
```yaml
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 1000m
    memory: 2Gi
```

### 调整写入限制
编辑 `loki-configmap-demo.yaml`:
```yaml
limits_config:
  ingestion_rate_mb: 20
  ingestion_burst_size_mb: 40
```

## 📁 文件说明

- `loki-configmap-demo.yaml` - Demo环境Loki配置
- `loki-deployment-demo.yaml` - Demo环境部署配置
- `loki-serviceaccount.yaml` - Workload Identity服务账号
- `deploy-loki-demo.sh` - 自动化部署脚本
- `setup-workload-identity.sh` - Workload Identity设置脚本

## 🆙 升级到生产环境

Demo环境验证后，可考虑以下生产级改进：
- 启用认证和多租户
- 使用持久化存储 (PVC)
- 配置多副本和自动伸缩
- 添加监控和告警
- 实施网络策略
- 配置备份策略

---

**环境类型**: Demo/测试  
**Loki版本**: 3.1.1  
**Kubernetes版本**: 1.28+  
**最后更新**: $(date +%Y-%m-%d) 