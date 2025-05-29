# mTLS Kafka 高可用集群配置

本文件夹包含部署启用mTLS的Kafka高可用集群所需的所有配置文件和自动化脚本。

## 📁 文件说明

### 必需配置文件

#### 1. `kafka-statefulset-ha-mtls.yaml`
- **用途**: Kafka集群的主要部署配置
- **特性**: 
  - 3节点高可用集群
  - KRaft模式（无需ZooKeeper）
  - 启用mTLS双向认证
  - 外部访问支持
  - 动态配置生成
  - 渐进式启动策略

#### 2. `kafka-service-mtls.yaml`
- **用途**: Kafka集群的网络服务配置
- **包含服务**:
  - `kafka`: ClusterIP服务（内部访问）
  - `kafka-headless`: 无头服务（服务发现）
  - `kafka-external-ssl`: LoadBalancer服务（外部mTLS访问）
- **特性**: 
  - GKE优化配置
  - 外部IP: 34.89.30.150
  - 端口映射: 9094, 9095, 9096

#### 3. `kafka-client-mtls-config.yaml`
- **用途**: mTLS客户端连接配置
- **包含**:
  - SSL客户端配置
  - 证书挂载配置
  - 连接示例

### 自动化脚本 (scripts/)

#### 1. `deploy-mtls-kafka.sh` ⭐ **统一部署脚本**
- **用途**: mTLS Kafka集群的统一部署脚本
- **特性**: 
  - 详细的环境检查（节点资源、存储类、RBAC权限等）
  - 交互式部署模式
  - 一键部署完整流程
  - 智能跳过已存在的资源
  - 带时间戳的详细日志输出
  - 多种操作模式和命令行选项
- **使用**: `./scripts/deploy-mtls-kafka.sh deploy`

#### 2. `generate-certs.sh`
- **用途**: 生成mTLS所需的SSL证书
- **功能**:
  - 生成CA证书和密钥
  - 创建服务器和客户端证书
  - 生成Java KeyStore和TrustStore
  - 自动创建Kubernetes Secret
- **使用**: `./scripts/generate-certs.sh`

#### 3. `verify-deployment.sh`
- **用途**: 验证Kafka集群部署和功能
- **测试项目**:
  - 基础Kafka功能（主题创建、消息生产/消费）
  - mTLS安全功能（双向认证、加密传输）
  - 集群健康状态检查
- **使用**: `./scripts/verify-deployment.sh`

## 🚀 快速部署

### 方法一：一键部署（推荐）
```bash
# 进入kafka目录
cd k8s/kafka/

# 一键部署mTLS Kafka集群
./scripts/deploy-mtls-kafka.sh deploy

# 验证部署
./scripts/verify-deployment.sh
```

### 方法二：分步部署
```bash
# 1. 生成证书
./scripts/generate-certs.sh

# 2. 部署集群
kubectl apply -f kafka-statefulset-ha-mtls.yaml
kubectl apply -f kafka-service-mtls.yaml
kubectl apply -f kafka-client-mtls-config.yaml

# 3. 验证部署
./scripts/verify-deployment.sh
```

### 方法三：手动部署
```bash
# 1. 前置条件
kubectl create namespace confluent-kafka

# 2. 生成证书
./scripts/generate-certs.sh

# 3. 部署服务
kubectl apply -f kafka-service-mtls.yaml

# 4. 部署StatefulSet
kubectl apply -f kafka-statefulset-ha-mtls.yaml

# 5. 部署客户端配置
kubectl apply -f kafka-client-mtls-config.yaml

# 6. 验证部署
kubectl get pods -n confluent-kafka
```

## 🔧 脚本使用指南

### deploy-mtls-kafka.sh 详细用法
```bash
# 查看帮助
./scripts/deploy-mtls-kafka.sh help

# 完整部署
./scripts/deploy-mtls-kafka.sh deploy

# 仅环境检查
./scripts/deploy-mtls-kafka.sh check

# 仅生成证书
./scripts/deploy-mtls-kafka.sh certs

# 跳过环境检查直接部署
./scripts/deploy-mtls-kafka.sh deploy --skip-check

# 跳过证书生成直接部署
./scripts/deploy-mtls-kafka.sh deploy --skip-certs

# 交互式部署
./scripts/deploy-mtls-kafka.sh deploy --interactive

# 查看集群状态
./scripts/deploy-mtls-kafka.sh status

# 清理集群
./scripts/deploy-mtls-kafka.sh cleanup
```

### 验证脚本用法
```bash
# 运行完整验证
./scripts/verify-deployment.sh

# 验证会测试：
# - 基础Kafka功能
# - mTLS安全功能
# - 集群健康状态
# - 生成验证报告
```

## 📋 脚本功能对比

| 脚本名称 | 用途 | 复杂度 | 推荐场景 |
|---------|------|--------|----------|
| `deploy-mtls-kafka.sh` | 统一部署脚本 | 中等 | **所有场景推荐** |
| `generate-certs.sh` | 证书生成 | 低 | 独立使用 |
| `verify-deployment.sh` | 部署验证 | 中等 | 验证测试 |

## 🔧 配置详情

### 集群规格
- **节点数**: 3个
- **复制因子**: 3
- **最小同步副本**: 2
- **存储**: 每节点100Gi SSD
- **资源**: 4-8Gi内存，1-2 CPU核

### 网络配置
- **内部监听器**: PLAINTEXT on port 9092
- **控制器监听器**: PLAINTEXT on port 9093  
- **外部监听器**: SSL/mTLS on port 9094
- **JMX监控**: port 9999

### 安全配置
- **mTLS认证**: 强制客户端证书验证
- **SSL终止**: 在Kafka层处理
- **证书位置**: `/opt/kafka/config/ssl/`
- **密码**: 统一使用"password"

## 🔍 连接信息

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

## 📋 管理命令

### 使用脚本管理
```bash
# 查看状态
./scripts/deploy-mtls-kafka.sh status

# 重新部署
./scripts/deploy-mtls-kafka.sh deploy --skip-certs

# 清理集群
./scripts/deploy-mtls-kafka.sh cleanup
```

### 手动管理
```bash
# 扩缩容
kubectl scale statefulset kafka --replicas=5 -n confluent-kafka

# 重启集群
kubectl rollout restart statefulset kafka -n confluent-kafka

# 查看日志
kubectl logs -f kafka-0 -n confluent-kafka
```

## 🗂️ 备份文件

不需要的配置文件已移动到 `../backup-configs/` 文件夹：
- `kafka-service-gke.yaml` - 重复的GKE服务配置
- `kafka-statefulset-simple*.yaml` - 非HA版本
- `kafka-statefulset.yaml` - 基础版本
- `kafka-service.yaml` - 非mTLS服务
- `kafka-hpa*.yaml` - HPA自动扩缩容配置

## ⚠️ 注意事项

1. **脚本权限**: 确保脚本有执行权限 `chmod +x scripts/*.sh`
2. **证书管理**: 确保SSL证书在过期前更新
3. **存储**: 使用SSD存储类以获得最佳性能
4. **网络**: 确保LoadBalancer正确分配外部IP
5. **监控**: 建议配置JMX监控和告警
6. **备份**: 定期备份Kafka数据和配置

## 🔗 相关文档

- [Kafka mTLS配置指南](../ssl/README.md)
- [GKE配置修复说明](../../GKE-配置修复说明.md)
- [文件整理总结](../../文件整理总结.md)
- [备份配置文件](../backup-configs/README.md) 