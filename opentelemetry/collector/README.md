# OpenTelemetry Collector 集群部署

这是一套完整的 OpenTelemetry Collector 集群部署方案，支持从 Kafka 的 3 个 topic（`otcol_logs`、`otcol_metrics`、`otcol_traces`）接收数据，并通过 mTLS 连接，然后将数据分别发送到 Loki、Mimir 和 Tempo。

## 架构概览

```
Kafka (mTLS) → LoadBalancer → 4x OpenTelemetry Collectors → Loki/Mimir/Tempo
```

- **Kafka Topics**: `otcol_logs`, `otcol_metrics`, `otcol_traces`
- **Collector 实例**: 4 个副本，支持自动扩缩容
- **输出目标**: 
  - 日志 → Loki
  - 指标 → Mimir (通过 Prometheus Remote Write)
  - 链路追踪 → Tempo

## 文件说明

| 文件名 | 描述 |
|--------|------|
| `namespace.yaml` | 创建 collector 命名空间 |
| `otel-collector-secret.yaml` | mTLS 证书配置 |
| `otel-collector-configmap.yaml` | OpenTelemetry Collector 主配置 |
| `otel-collector-rbac.yaml` | ServiceAccount 和 RBAC 权限 |
| `otel-collector-deployment.yaml` | Deployment 配置（4 副本） |
| `otel-collector-service.yaml` | Service 和 LoadBalancer 配置 |
| `otel-collector-hpa.yaml` | 水平自动扩缩容配置 |
| `otel-collector-servicemonitor.yaml` | Prometheus 监控配置 |
| `deploy.sh` | 一键部署脚本 |

## 部署前准备

### 1. 准备 mTLS 证书

您需要准备以下证书文件：
- `client.crt` - 客户端证书
- `client.key` - 客户端私钥
- `ca.crt` - CA 证书

### 2. 更新证书配置

编辑 `otel-collector-secret.yaml` 文件，将证书内容进行 base64 编码后替换：

```bash
# 编码证书文件
cat client.crt | base64 -w 0
cat client.key | base64 -w 0  
cat ca.crt | base64 -w 0
```

或者使用 kubectl 直接创建 Secret：

```bash
kubectl create secret generic otel-collector-certs \
  --from-file=client.crt=path/to/client.crt \
  --from-file=client.key=path/to/client.key \
  --from-file=ca.crt=path/to/ca.crt \
  -n collector
```

### 3. 更新配置

根据您的实际环境，更新 `otel-collector-configmap.yaml` 中的以下配置：

- **Kafka Brokers**: 更新 `brokers` 列表
- **Loki 端点**: 更新 `loki.endpoint`
- **Mimir 端点**: 更新 `prometheusremotewrite.endpoint`
- **Tempo 端点**: 更新 `otlp/tempo.endpoint`

## 部署步骤

### 方法 1: 使用部署脚本（推荐）

```bash
chmod +x deploy.sh
./deploy.sh
```

### 方法 2: 手动部署

```bash
# 1. 创建命名空间
kubectl apply -f namespace.yaml

# 2. 部署 RBAC
kubectl apply -f otel-collector-rbac.yaml

# 3. 部署证书 Secret
kubectl apply -f otel-collector-secret.yaml

# 4. 部署配置
kubectl apply -f otel-collector-configmap.yaml

# 5. 部署应用
kubectl apply -f otel-collector-deployment.yaml

# 6. 部署服务
kubectl apply -f otel-collector-service.yaml

# 7. 部署自动扩缩容
kubectl apply -f otel-collector-hpa.yaml

# 8. 部署监控（可选）
kubectl apply -f otel-collector-servicemonitor.yaml
```

## 验证部署

### 检查 Pod 状态

```bash
kubectl get pods -n collector
```

### 检查服务状态

```bash
kubectl get svc -n collector
```

### 查看日志

```bash
kubectl logs -f deployment/otel-collector -n collector
```

### 获取 LoadBalancer IP

```bash
kubectl get svc otel-collector-lb -n collector
```

## 监控和调试

### 访问健康检查端点

```bash
kubectl port-forward svc/otel-collector 13133:13133 -n collector
curl http://localhost:13133/
```

### 访问 zPages 调试页面

```bash
kubectl port-forward svc/otel-collector 55679:55679 -n collector
```

然后在浏览器中访问：
- http://localhost:55679/debug/servicez - 服务状态
- http://localhost:55679/debug/pipelinez - 管道状态

### 查看指标

```bash
kubectl port-forward svc/otel-collector 8888:8888 -n collector
curl http://localhost:8888/metrics
```

## 配置说明

### Kafka 接收器配置

- **协议版本**: 2.6.0
- **认证方式**: mTLS
- **编码格式**: OTLP Proto
- **消费者组**: 每个 topic 使用独立的消费者组

### 处理器配置

- **内存限制器**: 限制内存使用，防止 OOM
- **批处理器**: 优化数据传输效率
- **资源处理器**: 添加服务标识信息

### 导出器配置

- **Loki**: 日志数据，支持多租户
- **Prometheus Remote Write**: 指标数据到 Mimir
- **OTLP**: 链路追踪数据到 Tempo

## 自动扩缩容

HPA 配置：
- **最小副本数**: 4
- **最大副本数**: 12
- **CPU 阈值**: 70%
- **内存阈值**: 80%

## 故障排除

### 常见问题

1. **证书问题**
   ```bash
   kubectl logs deployment/otel-collector -n collector | grep -i tls
   ```

2. **Kafka 连接问题**
   ```bash
   kubectl logs deployment/otel-collector -n collector | grep -i kafka
   ```

3. **内存不足**
   ```bash
   kubectl top pods -n collector
   ```

### 调试命令

```bash
# 进入 Pod 调试
kubectl exec -it deployment/otel-collector -n collector -- /bin/sh

# 查看配置文件
kubectl exec deployment/otel-collector -n collector -- cat /etc/otel-collector-config/config.yaml

# 查看证书
kubectl exec deployment/otel-collector -n collector -- ls -la /etc/ssl/certs/
```

## 性能调优

### 资源配置

根据实际负载调整 `otel-collector-deployment.yaml` 中的资源配置：

```yaml
resources:
  limits:
    cpu: 1000m      # 根据需要调整
    memory: 1Gi     # 根据需要调整
  requests:
    cpu: 200m
    memory: 400Mi
```

### 批处理优化

在 `otel-collector-configmap.yaml` 中调整批处理参数：

```yaml
batch:
  timeout: 1s              # 批处理超时时间
  send_batch_size: 1024    # 批处理大小
  send_batch_max_size: 2048 # 最大批处理大小
```

## 安全注意事项

1. **证书管理**: 定期轮换 mTLS 证书
2. **网络策略**: 配置适当的网络策略限制访问
3. **RBAC**: 最小权限原则
4. **Secret 管理**: 使用 Kubernetes Secret 或外部密钥管理系统

## 升级和维护

### 升级 Collector 版本

1. 更新 `otel-collector-deployment.yaml` 中的镜像版本
2. 应用更新：
   ```bash
   kubectl apply -f otel-collector-deployment.yaml
   ```

### 配置更新

1. 更新 `otel-collector-configmap.yaml`
2. 重启 Deployment：
   ```bash
   kubectl rollout restart deployment/otel-collector -n collector
   ```

## 支持

如有问题，请检查：
1. Kubernetes 集群状态
2. 网络连接性
3. 证书有效性
4. 目标服务（Loki/Mimir/Tempo）状态 