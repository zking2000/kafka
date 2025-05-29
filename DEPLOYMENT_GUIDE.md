# mTLS Kafka 高可用集群完整部署指南

## 🎯 概述

本指南提供了部署启用mTLS的Kafka高可用集群的完整流程，包括所有必需的配置文件和自动化脚本。

## 📁 文件结构

```
k8s/kafka/
├── kafka-statefulset-ha-mtls.yaml    # 主要部署配置
├── kafka-service-mtls.yaml           # 网络服务配置
├── kafka-client-mtls-config.yaml     # 客户端配置
├── README.md                          # 详细说明文档
├── DEPLOYMENT_GUIDE.md               # 本部署指南
└── scripts/                          # 自动化脚本
    ├── deploy-mtls-kafka.sh          # ⭐ 统一部署脚本
    ├── generate-certs.sh             # 证书生成脚本
    ├── verify-deployment.sh          # 验证脚本
    └── README.md                     # 脚本详细说明
```

## 🚀 快速开始

### 方法一：一键部署（推荐）

```bash
# 1. 进入kafka目录
cd k8s/kafka/

# 2. 一键部署
./scripts/deploy-mtls-kafka.sh deploy

# 3. 验证部署
./scripts/verify-deployment.sh

# 4. 查看状态
./scripts/deploy-mtls-kafka.sh status
```

### 方法二：分步部署

```bash
# 1. 生成证书
./scripts/generate-certs.sh

# 2. 部署集群
kubectl apply -f kafka-service-mtls.yaml
kubectl apply -f kafka-statefulset-ha-mtls.yaml
kubectl apply -f kafka-client-mtls-config.yaml

# 3. 等待集群就绪
kubectl wait --for=condition=ready pod -l app=kafka -n confluent-kafka --timeout=600s

# 4. 验证部署
./scripts/verify-deployment.sh
```

## 🔧 详细部署步骤

### 1. 环境准备

**检查必要工具:**
```bash
# 检查kubectl
kubectl version --client

# 检查openssl
openssl version

# 检查keytool
keytool -help

# 检查集群连接
kubectl cluster-info
```

**检查集群资源:**
```bash
# 检查节点
kubectl get nodes

# 检查存储类
kubectl get storageclass

# 检查命名空间
kubectl get namespace confluent-kafka || kubectl create namespace confluent-kafka
```

### 2. 证书生成

**自动生成（推荐）:**
```bash
./scripts/generate-certs.sh
```

**手动生成:**
```bash
# 创建证书目录
mkdir -p ../../../certs && cd ../../../certs

# 生成CA证书
openssl genrsa -out ca.key 2048
openssl req -new -x509 -key ca.key -sha256 -subj "/C=CN/ST=Beijing/L=Beijing/O=Kafka/OU=IT/CN=KafkaCA" -days 365 -out ca.crt

# 生成服务器证书
openssl genrsa -out kafka.key 2048
# ... (详细步骤见generate-certs.sh)

# 创建Kubernetes Secret
kubectl create secret generic kafka-keystore -n confluent-kafka \
    --from-file=kafka.server.keystore.jks \
    --from-file=kafka.server.truststore.jks \
    --from-file=client.keystore.jks \
    --from-literal=keystore-password=password \
    --from-literal=truststore-password=password
```

### 3. 集群部署

**使用脚本部署:**
```bash
./scripts/deploy-mtls-kafka.sh kafka
```

**手动部署:**
```bash
# 部署服务
kubectl apply -f kafka-service-mtls.yaml

# 部署StatefulSet
kubectl apply -f kafka-statefulset-ha-mtls.yaml

# 部署客户端配置
kubectl apply -f kafka-client-mtls-config.yaml
```

### 4. 验证部署

**自动验证:**
```bash
./scripts/verify-deployment.sh
```

**手动验证:**
```bash
# 检查pods状态
kubectl get pods -n confluent-kafka

# 检查服务状态
kubectl get svc -n confluent-kafka

# 测试内部连接
kubectl exec -it kafka-0 -n confluent-kafka -- /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server kafka-0.kafka-headless.confluent-kafka.svc.cluster.local:9092 \
    --list

# 测试mTLS连接
kubectl exec -it kafka-mtls-test-client -n confluent-kafka -- /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server kafka-0.kafka-headless.confluent-kafka.svc.cluster.local:9094 \
    --command-config /tmp/mtls-client.properties \
    --list
```

## 🔍 配置详情

### 集群配置
- **节点数**: 3个（kafka-0, kafka-1, kafka-2）
- **模式**: KRaft（无ZooKeeper依赖）
- **复制因子**: 3
- **最小同步副本**: 2
- **存储**: 每节点100Gi SSD

### 网络配置
- **内部端口**: 9092 (PLAINTEXT)
- **控制器端口**: 9093 (PLAINTEXT)
- **外部mTLS端口**: 9094 (SSL)
- **JMX端口**: 9999
- **外部IP**: 34.89.30.150
- **外部端口映射**: 9094, 9095, 9096

### 安全配置
- **协议**: SSL/TLS 1.2+
- **认证**: 双向SSL认证（mTLS）
- **证书类型**: X.509
- **密钥长度**: 2048位
- **有效期**: 365天
- **密码**: "password"

## 🔗 连接信息

### 内部连接（集群内）
```properties
bootstrap.servers=kafka-0.kafka-headless.confluent-kafka.svc.cluster.local:9092,kafka-1.kafka-headless.confluent-kafka.svc.cluster.local:9092,kafka-2.kafka-headless.confluent-kafka.svc.cluster.local:9092
```

### 外部mTLS连接
```properties
bootstrap.servers=34.89.30.150:9094,34.89.30.150:9095,34.89.30.150:9096
security.protocol=SSL
ssl.keystore.location=client.keystore.jks
ssl.keystore.password=password
ssl.key.password=password
ssl.truststore.location=kafka.server.truststore.jks
ssl.truststore.password=password
ssl.endpoint.identification.algorithm=
```

### 获取证书文件
```bash
# 从Kubernetes Secret提取证书
kubectl get secret kafka-keystore -n confluent-kafka -o jsonpath='{.data.client\.keystore\.jks}' | base64 -d > client.keystore.jks
kubectl get secret kafka-keystore -n confluent-kafka -o jsonpath='{.data.kafka\.server\.truststore\.jks}' | base64 -d > kafka.server.truststore.jks
```

## 📋 管理操作

### 集群管理
```bash
# 查看状态
./scripts/deploy-mtls-kafka.sh status

# 扩缩容
kubectl scale statefulset kafka --replicas=5 -n confluent-kafka

# 重启集群
kubectl rollout restart statefulset kafka -n confluent-kafka

# 查看日志
kubectl logs -f kafka-0 -n confluent-kafka
```

### 主题管理
```bash
# 创建主题
kubectl exec kafka-0 -n confluent-kafka -- /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server kafka-0.kafka-headless.confluent-kafka.svc.cluster.local:9092 \
    --create --topic my-topic --partitions 6 --replication-factor 3

# 列出主题
kubectl exec kafka-0 -n confluent-kafka -- /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server kafka-0.kafka-headless.confluent-kafka.svc.cluster.local:9092 \
    --list

# 查看主题详情
kubectl exec kafka-0 -n confluent-kafka -- /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server kafka-0.kafka-headless.confluent-kafka.svc.cluster.local:9092 \
    --describe --topic my-topic
```

### 证书管理
```bash
# 检查证书有效期
openssl x509 -in ../../../certs/kafka.crt -text -noout | grep "Not After"

# 更新证书
kubectl delete secret kafka-keystore kafka-tls-certs -n confluent-kafka
./scripts/generate-certs.sh
kubectl rollout restart statefulset kafka -n confluent-kafka

# 备份证书
kubectl get secret kafka-keystore -n confluent-kafka -o yaml > kafka-keystore-backup.yaml
```

## 🚨 故障排查

### 常见问题

**1. Pods启动失败**
```bash
# 查看Pod状态
kubectl get pods -n confluent-kafka

# 查看详细事件
kubectl describe pod kafka-0 -n confluent-kafka

# 查看日志
kubectl logs kafka-0 -n confluent-kafka

# 检查资源限制
kubectl top pods -n confluent-kafka
```

**2. 证书问题**
```bash
# 检查证书Secret
kubectl get secret kafka-keystore -n confluent-kafka

# 检查证书挂载
kubectl exec kafka-0 -n confluent-kafka -- ls -la /opt/kafka/config/ssl/

# 验证证书
kubectl exec kafka-0 -n confluent-kafka -- keytool -list -keystore /opt/kafka/config/ssl/kafka.server.keystore.jks -storepass password
```

**3. 网络连接问题**
```bash
# 检查服务状态
kubectl get svc -n confluent-kafka

# 检查LoadBalancer
kubectl describe svc kafka-external-ssl -n confluent-kafka

# 测试内部连接
kubectl exec kafka-0 -n confluent-kafka -- nc -zv kafka-1.kafka-headless.confluent-kafka.svc.cluster.local 9092
```

**4. mTLS连接失败**
```bash
# 检查SSL配置
kubectl exec kafka-0 -n confluent-kafka -- grep ssl /opt/kafka/config/server.properties

# 测试SSL连接
kubectl exec kafka-0 -n confluent-kafka -- openssl s_client -connect kafka-0.kafka-headless.confluent-kafka.svc.cluster.local:9094 -cert /opt/kafka/config/ssl/client.crt -key /opt/kafka/config/ssl/client.key
```

### 日志分析
```bash
# 查看启动日志
kubectl logs kafka-0 -n confluent-kafka | grep -i "started"

# 查看错误日志
kubectl logs kafka-0 -n confluent-kafka | grep -i "error\|exception\|failed"

# 查看SSL相关日志
kubectl logs kafka-0 -n confluent-kafka | grep -i "ssl\|tls\|certificate"

# 实时监控日志
kubectl logs -f kafka-0 -n confluent-kafka
```

## 🧹 清理操作

### 完全清理
```bash
./scripts/deploy-mtls-kafka.sh cleanup
```

### 手动清理
```bash
# 删除StatefulSet
kubectl delete statefulset kafka -n confluent-kafka

# 删除服务
kubectl delete svc kafka kafka-headless kafka-external-ssl -n confluent-kafka

# 删除PVC（数据）
kubectl delete pvc -l app=kafka -n confluent-kafka

# 删除证书
kubectl delete secret kafka-keystore kafka-tls-certs -n confluent-kafka

# 删除命名空间（可选）
kubectl delete namespace confluent-kafka
```

## 📊 监控和告警

### JMX监控
```bash
# 端口转发JMX端口
kubectl port-forward kafka-0 9999:9999 -n confluent-kafka

# 使用JConsole连接
jconsole localhost:9999
```

### 健康检查
```bash
# 检查集群健康
./scripts/verify-deployment.sh

# 检查主题状态
kubectl exec kafka-0 -n confluent-kafka -- /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server kafka-0.kafka-headless.confluent-kafka.svc.cluster.local:9092 \
    --describe --under-replicated-partitions

# 检查消费者组
kubectl exec kafka-0 -n confluent-kafka -- /opt/kafka/bin/kafka-consumer-groups.sh \
    --bootstrap-server kafka-0.kafka-headless.confluent-kafka.svc.cluster.local:9092 \
    --list
```

## 🔗 相关文档

- [详细配置说明](README.md)
- [脚本使用指南](scripts/README.md)
- [备份配置文件](../backup-configs/README.md)
- [GKE配置修复说明](../../GKE-配置修复说明.md)
- [文件整理总结](../../文件整理总结.md)

## 📞 支持

如果遇到问题，请：
1. 查看本指南的故障排查部分
2. 运行验证脚本获取详细报告
3. 检查Kubernetes事件和日志
4. 参考相关文档 