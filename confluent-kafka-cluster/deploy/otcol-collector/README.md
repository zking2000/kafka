# OpenTelemetry Collector - Kafka Consumer

这个目录包含了用于部署OpenTelemetry Collector的Kubernetes清单文件，该Collector作为消费者连接到启用了mTLS的Kafka集群，从指定的topics中消费可观测性数据并转发到相应的后端存储。

## 📋 功能概述

- **Kafka接收器**：从mTLS启用的Kafka集群消费数据
- **多管道支持**：分别处理日志、指标和链路追踪数据
- **后端存储**：
  - 📊 **日志** → Loki
  - 📈 **指标** → Mimir  
  - 🔍 **链路追踪** → Tempo
- **监控和可观测性**：内置健康检查、指标暴露和调试功能
- **高可用性**：支持水平扩展和自动故障恢复

## 🏗️ 架构

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Kafka Topics  │    │ OTel Collector  │    │  Backend Store  │
├─────────────────┤    ├─────────────────┤    ├─────────────────┤
│ otcol_logs      │────│ kafka/logs      │────│ Loki            │
│ otcol_metrics   │────│ kafka/metrics   │────│ Mimir           │
│ otcol_traces    │────│ kafka/traces    │────│ Tempo           │
└─────────────────┘    └─────────────────┘    └─────────────────┘
       ↑ mTLS                    │                       │
       │                         │                       │
    SSL Certs              Processing                Export
    (Secret)               & Batching               (HTTP/gRPC)
```

## 📁 文件结构

```
deploy/otcol-collector/
├── otelcol-config.yaml     # OTel Collector配置
├── deployment.yaml         # Kubernetes Deployment
├── service.yaml           # Kubernetes Services
├── rbac.yaml             # ServiceAccount & RBAC
├── hpa.yaml              # 水平Pod自动扩缩容
├── network-policy.yaml   # 网络策略
├── kustomization.yaml    # Kustomize配置
├── deploy.sh            # 部署脚本
└── README.md           # 本文档
```

## 🚀 快速开始

### 前置条件

1. **Kubernetes集群**已就绪
2. **Kafka集群**已部署并启用mTLS
3. **SSL证书Secret** `kafka-ssl-certs` 已创建
4. **Grafana Stack**已部署 (Loki, Mimir, Tempo)

### 部署步骤

1. **克隆或下载**这些配置文件
2. **修改配置**以适应您的环境
3. **运行部署脚本**：

```bash
# 进入目录
cd deploy/otcol-collector

# 给脚本执行权限
chmod +x deploy.sh

# 部署collector
./deploy.sh deploy
```

### 验证部署

```bash
# 验证部署状态
./deploy.sh verify

# 查看Pod状态
kubectl get pods -n confluent-kafka -l app=otelcol

# 查看日志
./deploy.sh logs
```

## ⚙️ 配置说明

### Kafka连接配置

```yaml
brokers:
  - kafka-0.kafka-headless.confluent-kafka.svc.cluster.local:9092
  - kafka-1.kafka-headless.confluent-kafka.svc.cluster.local:9092
  - kafka-2.kafka-headless.confluent-kafka.svc.cluster.local:9092

auth:
  tls:
    cert_file: /etc/kafka/secrets/kafka.client.keystore.jks
    key_file: /etc/kafka/secrets/kafka.client.keystore.jks
    ca_file: /etc/kafka/secrets/kafka.client.truststore.jks
```

### Topics配置

| Topic | 用途 | 后端存储 |
|-------|------|----------|
| `otcol_logs` | 日志数据 | Loki |
| `otcol_metrics` | 指标数据 | Mimir |
| `otcol_traces` | 链路追踪数据 | Tempo |

### 资源配置

```yaml
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 1Gi
```

## 🔧 自定义配置

### 修改后端存储地址

编辑 `otelcol-config.yaml` 中的exporters部分：

```yaml
exporters:
  loki:
    endpoint: http://your-loki.namespace.svc.cluster.local:3100/loki/api/v1/push
  
  prometheusremotewrite/mimir:
    endpoint: http://your-mimir.namespace.svc.cluster.local:8080/api/v1/push
    
  otlp/tempo:
    endpoint: http://your-tempo.namespace.svc.cluster.local:4317
```

### 调整副本数和资源

编辑 `kustomization.yaml`：

```yaml
replicas:
- name: otelcol-kafka-consumer
  count: 3  # 调整副本数

patches:
- target:
    kind: Deployment
    name: otelcol-kafka-consumer
  patch: |-
    - op: replace
      path: /spec/template/spec/containers/0/resources/limits/memory
      value: "2Gi"  # 调整内存限制
```

### 修改批处理配置

在 `otelcol-config.yaml` 中调整processors：

```yaml
processors:
  batch/logs:
    timeout: 10s           # 批处理超时
    send_batch_size: 2048  # 批处理大小
    send_batch_max_size: 4096
```

## 📊 监控和观测

### 内置监控端点

| 端点 | 端口 | 用途 |
|------|------|------|
| `/health` | 13133 | 健康检查 |
| `/metrics` | 8889 | Prometheus指标 |
| `/debug/pprof` | 1777 | 性能分析 |
| `/debug/zpages` | 55679 | zPages调试 |

### 查看指标

```bash
# Port-forward到指标端口
kubectl port-forward -n confluent-kafka svc/otelcol-kafka-consumer 8889:8889

# 访问指标
curl http://localhost:8889/metrics
```

### 健康检查

```bash
# 检查健康状态
kubectl exec -n confluent-kafka deployment/otelcol-kafka-consumer -- \
  curl -s http://localhost:13133/health
```

## 🛠️ 故障排除

### 常见问题

1. **SSL连接失败**
   ```bash
   # 检查SSL证书
   kubectl describe secret kafka-ssl-certs -n confluent-kafka
   
   # 验证证书挂载
   kubectl exec deployment/otelcol-kafka-consumer -n confluent-kafka -- \
     ls -la /etc/kafka/secrets/
   ```

2. **Topics不存在**
   ```bash
   # 创建topics
   ./deploy.sh topics
   ```

3. **后端连接失败**
   ```bash
   # 检查网络策略
   kubectl describe networkpolicy otelcol-kafka-consumer-netpol -n confluent-kafka
   
   # 测试连接
   kubectl exec deployment/otelcol-kafka-consumer -n confluent-kafka -- \
     nc -zv loki.grafana-stack.svc.cluster.local 3100
   ```

### 日志分析

```bash
# 查看详细日志
kubectl logs -n confluent-kafka -l app=otelcol --tail=100

# 过滤错误日志
kubectl logs -n confluent-kafka -l app=otelcol | grep -i error

# 实时查看日志
./deploy.sh logs
```

## 📈 性能调优

### 水平扩展

```bash
# 手动扩展
kubectl scale deployment otelcol-kafka-consumer -n confluent-kafka --replicas=5

# 自动扩展 (HPA已配置)
kubectl get hpa -n confluent-kafka
```

### 内存和CPU优化

1. **增加内存限制**以处理更大的批处理
2. **调整批处理参数**以提高吞吐量
3. **启用压缩**以减少网络开销

### Kafka Consumer调优

```yaml
consumer:
  offset: earliest          # 从最早的消息开始
  session_timeout: 30s      # 会话超时时间
  heartbeat_interval: 3s    # 心跳间隔
```

## 🔒 安全考虑

1. **mTLS认证**：使用客户端证书进行身份验证
2. **网络策略**：限制Pod间通信
3. **RBAC**：最小权限原则
4. **Secret管理**：安全存储SSL证书

## 🚫 清理

```bash
# 清理部署
./deploy.sh cleanup

# 删除topics (可选)
kubectl exec kafka-0 -n confluent-kafka -- \
  kafka-topics --delete --topic otcol_logs --bootstrap-server localhost:9092
```

## 📞 支持

如有问题，请：

1. 检查日志和事件
2. 验证网络连接
3. 确认配置正确性
4. 查看Kubernetes资源状态

---

**注意**：请根据实际环境调整配置参数，特别是endpoint地址、认证信息和资源限制。 