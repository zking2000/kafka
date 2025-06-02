# Kafka 端口配置指南

本文档详细说明了Kafka集群中各个端口的作用、配置和使用场景。

## 概览

当前Kafka集群运行在KRaft模式（无Zookeeper），配置了多个端口用于不同的通信需求：

| 端口 | 监听器名称 | 协议 | 用途 | 访问范围 |
|------|------------|------|------|----------|
| 9092 | INTERNAL_SSL | SSL | 内部broker通信 | 集群内部 |
| 9093 | EXTERNAL_SSL | SSL | 外部客户端连接 | 外部访问 |
| 9094 | CONTROLLER | SSL | Controller选举和元数据同步 | 集群内部 |
| 9095 | KRAFT_API | PLAINTEXT | KRaft API管理 | 集群内部 |
| 9999 | JMX | TCP | JMX监控 | 监控客户端 |

## 详细端口说明

### 9092端口 - INTERNAL_SSL

**配置:**
```yaml
INTERNAL_SSL://0.0.0.0:9092
security.protocol: SSL
listener.security.protocol.map: INTERNAL_SSL:SSL
```

**作用:**
- Kafka broker之间的内部SSL通信
- 数据复制和同步
- 集群内部服务发现

**访问地址:**
```
kafka-0.kafka-headless.confluent-kafka.svc.cluster.local:9092
kafka-1.kafka-headless.confluent-kafka.svc.cluster.local:9092
kafka-2.kafka-headless.confluent-kafka.svc.cluster.local:9092
```

**认证要求:**
- ✅ 需要SSL/TLS
- ✅ 需要客户端证书（mTLS）
- ✅ 证书验证

**使用场景:**
- Kafka inter-broker通信
- 内部复制流量
- 分区leader选举通信

---

### 9093端口 - EXTERNAL_SSL ⭐

**配置:**
```yaml
EXTERNAL_SSL://0.0.0.0:9093
security.protocol: SSL
listener.security.protocol.map: EXTERNAL_SSL:SSL
```

**作用:**
- **外部客户端的主要连接端口**
- 生产者和消费者连接
- 外部应用程序访问

**访问地址:**
```
# 通过Cloud DNS
kafka-0.kafka.internal.cloud:9093
kafka-1.kafka.internal.cloud:9093
kafka-2.kafka.internal.cloud:9093

# 通过LoadBalancer外部IP
10.0.0.36:9093
10.0.0.37:9093
10.0.0.38:9093
```

**认证要求:**
- ✅ 需要SSL/TLS
- ✅ 需要客户端证书（mTLS）
- ✅ 证书验证
- ✅ 支持SNI（Server Name Indication）

**使用场景:**
- ⭐ **OpenTelemetry Collector连接**
- 外部应用程序
- 生产环境客户端
- 跨网络访问

**配置示例:**
```yaml
# OpenTelemetry Kafka Exporter配置
brokers:
  - kafka-0.kafka.internal.cloud:9093
  - kafka-1.kafka.internal.cloud:9093
  - kafka-2.kafka.internal.cloud:9093
tls:
  cert_file: /etc/ssl/certs/client-cert.pem
  key_file: /etc/ssl/private/client-key.pem
  ca_file: /etc/ssl/certs/ca-cert.pem
  server_name_override: "kafka.internal.cloud"
```

---

### 9094端口 - CONTROLLER ⚠️

**配置:**
```yaml
CONTROLLER://0.0.0.0:9094
security.protocol: SSL
listener.security.protocol.map: CONTROLLER:SSL
```

**作用:**
- KRaft模式Controller选举
- 元数据同步和复制
- 集群状态管理

**访问地址:**
```
kafka-0.kafka-headless.confluent-kafka.svc.cluster.local:9094
kafka-1.kafka-headless.confluent-kafka.svc.cluster.local:9094
kafka-2.kafka-headless.confluent-kafka.svc.cluster.local:9094
```

**认证要求:**
- ✅ 需要SSL/TLS
- ✅ Controller专用证书
- ✅ 严格的证书验证

**⚠️ 重要警告:**
- **不得用于客户端连接**
- 仅限Controller节点间通信
- 连接此端口会导致认证失败

**使用场景:**
- KRaft Controller选举
- 元数据日志复制
- 集群拓扑更新

---

### 9095端口 - KRAFT_API

**配置:**
```yaml
KRAFT_API://0.0.0.0:9095
security.protocol: PLAINTEXT
listener.security.protocol.map: KRAFT_API:PLAINTEXT
```

**作用:**
- KRaft API管理端点
- 健康检查
- 管理工具访问

**访问地址:**
```
kafka-0.kafka-headless.confluent-kafka.svc.cluster.local:9095
kafka-1.kafka-headless.confluent-kafka.svc.cluster.local:9095
kafka-2.kafka-headless.confluent-kafka.svc.cluster.local:9095
```

**认证要求:**
- ❌ 无SSL/TLS（明文）
- ❌ 无客户端证书
- ⚠️ 仅限集群内部访问

**使用场景:**
- 健康检查脚本
- 管理工具
- 监控系统
- 内部API调用

---

### 9999端口 - JMX

**配置:**
```yaml
containerPort: 9999
name: jmx
protocol: TCP
```

**作用:**
- JMX（Java Management Extensions）监控
- 性能指标收集
- 运行时管理

**访问地址:**
```
kafka-0:9999
kafka-1:9999
kafka-2:9999
```

**认证要求:**
- 配置依赖（通常无认证或基本认证）
- JMX客户端连接

**使用场景:**
- Prometheus JMX Exporter
- 性能监控工具
- 调试和诊断
- 运维管理

## 客户端连接建议

### 推荐配置

**外部客户端（如OpenTelemetry）:**
```yaml
# 使用9093端口 - EXTERNAL_SSL
brokers:
  - kafka-0.kafka.internal.cloud:9093
  - kafka-1.kafka.internal.cloud:9093
  - kafka-2.kafka.internal.cloud:9093
```

**内部客户端（如集群内应用）:**
```yaml
# 可使用9092端口 - INTERNAL_SSL
brokers:
  - kafka-0.kafka-headless.confluent-kafka.svc.cluster.local:9092
  - kafka-1.kafka-headless.confluent-kafka.svc.cluster.local:9092
  - kafka-2.kafka-headless.confluent-kafka.svc.cluster.local:9092
```

### 避免的配置

❌ **不要连接Controller端口:**
```yaml
# 错误 - 不要这样配置
brokers:
  - kafka-0.kafka.internal.cloud:9094  # Controller端口
```

❌ **不要在生产环境使用明文端口:**
```yaml
# 错误 - 安全风险
brokers:
  - kafka-0.kafka.internal.cloud:9095  # 明文连接
```

## 故障排查

### 常见错误

1. **"unknown certificate" 错误:**
   - 原因：可能连接了错误的端口（如9094）
   - 解决：使用正确的端口（9093用于外部连接）

2. **"connection refused" 错误:**
   - 原因：端口不可访问或配置错误
   - 解决：检查网络策略和LoadBalancer配置

3. **"certificate signed by unknown authority" 错误:**
   - 原因：CA证书不匹配
   - 解决：确保使用正确的CA证书文件

### 调试命令

**测试SSL连接:**
```bash
openssl s_client -connect kafka-0.kafka.internal.cloud:9093 \
  -cert client.crt -key client.key -CAfile ca.crt \
  -servername kafka.internal.cloud -verify_return_error
```

**检查端口可达性:**
```bash
nc -zv kafka-0.kafka.internal.cloud 9093
```

**查看证书信息:**
```bash
openssl x509 -in client.crt -text -noout | grep Subject
```

## 版本变更说明

| 版本 | 变更 | 影响 |
|------|------|------|
| 初始版本 | 错误使用9094端口 | 客户端连接失败 |
| 当前版本 | 修正为9093端口 | mTLS连接正常 |

---

**最后更新:** 2025-06-02  
**适用版本:** Confluent Kafka with KRaft mode 