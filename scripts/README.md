# Kafka mTLS 集群自动化脚本

本文件夹包含部署和管理mTLS Kafka集群的所有自动化脚本。

## 📁 脚本列表

### 🚀 主要部署脚本

#### `deploy-mtls-kafka.sh` ⭐ **统一部署脚本**
整合了所有部署功能的统一脚本，适用于所有场景。

**功能特性:**
- ✅ 详细的环境检查（节点资源、存储类、RBAC权限等）
- ✅ 交互式部署模式
- ✅ 智能证书管理（自动跳过已存在的证书）
- ✅ 一键部署完整集群
- ✅ 自动验证部署结果
- ✅ 带时间戳的详细日志输出
- ✅ 多种操作模式和命令行选项

**使用方法:**
```bash
# 查看帮助
./deploy-mtls-kafka.sh help

# 一键部署（推荐）
./deploy-mtls-kafka.sh deploy

# 仅环境检查
./deploy-mtls-kafka.sh check

# 仅生成证书
./deploy-mtls-kafka.sh certs

# 交互式部署
./deploy-mtls-kafka.sh deploy --interactive

# 跳过环境检查直接部署
./deploy-mtls-kafka.sh deploy --skip-check

# 查看集群状态
./deploy-mtls-kafka.sh status

# 清理集群
./deploy-mtls-kafka.sh cleanup
```

### 🔐 证书管理脚本

#### `generate-certs.sh`
生成mTLS所需的完整SSL证书体系。

**生成内容:**
- CA根证书和私钥
- Kafka服务器证书（支持多域名）
- 客户端证书
- Java KeyStore (JKS格式)
- Java TrustStore
- Kubernetes Secret

**证书配置:**
- 有效期: 365天
- 密钥长度: 2048位
- 密码: "password"
- 支持的域名:
  - `kafka-*.kafka-headless.confluent-kafka.svc.cluster.local`
  - `kafka.confluent-kafka.svc.cluster.local`
  - `localhost`

**使用方法:**
```bash
./generate-certs.sh
```

**输出文件:**
```
certs/
├── ca.crt                           # CA证书
├── ca.key                           # CA私钥
├── kafka.crt                        # Kafka服务器证书
├── kafka.key                        # Kafka服务器私钥
├── client.crt                       # 客户端证书
├── client.key                       # 客户端私钥
├── kafka.server.keystore.jks        # 服务器KeyStore
├── kafka.server.truststore.jks      # TrustStore
└── client.keystore.jks              # 客户端KeyStore
```

### 🔍 验证脚本

#### `verify-deployment.sh`
全面验证Kafka集群的部署和功能。

**验证项目:**
1. **环境检查**
   - kubectl可用性
   - 集群连接状态
   
2. **集群状态检查**
   - 命名空间存在性
   - 所有Kafka pods就绪状态
   
3. **基础功能测试**
   - 主题创建和列表
   - 消息生产和消费
   - 集群内部通信
   
4. **mTLS安全测试**
   - 双向SSL认证
   - 加密传输验证
   - 客户端证书验证
   
5. **报告生成**
   - 详细的验证报告
   - 时间戳命名
   - 问题诊断信息

**使用方法:**
```bash
./verify-deployment.sh
```

**输出示例:**
```
[INFO] 检查依赖工具...
[SUCCESS] 依赖检查通过
[INFO] 检查Kafka集群状态...
[SUCCESS] 所有Kafka pods运行正常
[INFO] 开始测试基础Kafka功能...
[SUCCESS] 基础Kafka功能测试完成
[INFO] 开始测试mTLS功能...
[SUCCESS] mTLS功能测试完成
[SUCCESS] 生成验证报告: kafka-verification-report-20250529-123456.txt
```

## 🔧 脚本使用最佳实践

### 1. 首次部署流程
```bash
# 1. 检查环境
./deploy-mtls-kafka.sh help

# 2. 一键部署
./deploy-mtls-kafka.sh deploy

# 3. 验证部署
./verify-deployment.sh

# 4. 查看状态
./deploy-mtls-kafka.sh status
```

### 2. 重新部署流程
```bash
# 如果证书已存在，跳过证书生成
./deploy-mtls-kafka.sh deploy --skip-certs

# 或者完全清理后重新部署
./deploy-mtls-kafka.sh cleanup
./deploy-mtls-kafka.sh deploy
```

### 3. 证书更新流程
```bash
# 1. 备份现有证书
kubectl get secret kafka-keystore -n confluent-kafka -o yaml > kafka-keystore-backup.yaml

# 2. 删除旧证书
kubectl delete secret kafka-keystore kafka-tls-certs -n confluent-kafka

# 3. 生成新证书
./generate-certs.sh

# 4. 重启Kafka集群
kubectl rollout restart statefulset kafka -n confluent-kafka
```

### 4. 故障排查流程
```bash
# 1. 查看集群状态
./deploy-mtls-kafka.sh status

# 2. 运行验证脚本
./verify-deployment.sh

# 3. 查看详细日志
kubectl logs -f kafka-0 -n confluent-kafka

# 4. 检查证书状态
kubectl get secret kafka-keystore -n confluent-kafka
```

## 📋 脚本参数说明

### deploy-mtls-kafka.sh 参数
| 参数 | 说明 | 示例 |
|------|------|------|
| `deploy` | 完整部署流程 | `./deploy-mtls-kafka.sh deploy` |
| `check` | 仅环境检查 | `./deploy-mtls-kafka.sh check` |
| `certs` | 仅生成证书 | `./deploy-mtls-kafka.sh certs` |
| `kafka` | 仅部署Kafka | `./deploy-mtls-kafka.sh kafka` |
| `verify` | 仅运行验证 | `./deploy-mtls-kafka.sh verify` |
| `status` | 查看状态 | `./deploy-mtls-kafka.sh status` |
| `cleanup` | 清理集群 | `./deploy-mtls-kafka.sh cleanup` |
| `--skip-check` | 跳过环境检查 | `./deploy-mtls-kafka.sh deploy --skip-check` |
| `--skip-certs` | 跳过证书生成 | `./deploy-mtls-kafka.sh deploy --skip-certs` |
| `--skip-verify` | 跳过验证 | `./deploy-mtls-kafka.sh deploy --skip-verify` |
| `--interactive` | 交互式模式 | `./deploy-mtls-kafka.sh deploy --interactive` |
| `--namespace` | 指定命名空间 | `./deploy-mtls-kafka.sh deploy --namespace my-kafka` |
| `--log-file` | 指定日志文件 | `./deploy-mtls-kafka.sh deploy --log-file /tmp/my.log` |

## 🚨 常见问题和解决方案

### 1. 证书相关问题
**问题**: 证书生成失败
```bash
# 解决方案
# 检查openssl和keytool是否安装
which openssl keytool

# 检查权限
ls -la ../../../certs/

# 重新生成
rm -rf ../../../certs/
./generate-certs.sh
```

**问题**: 证书过期
```bash
# 检查证书有效期
openssl x509 -in ../../../certs/kafka.crt -text -noout | grep "Not After"

# 更新证书
kubectl delete secret kafka-keystore kafka-tls-certs -n confluent-kafka
./generate-certs.sh
kubectl rollout restart statefulset kafka -n confluent-kafka
```

### 2. 部署相关问题
**问题**: Pods启动失败
```bash
# 查看Pod状态
kubectl get pods -n confluent-kafka

# 查看详细事件
kubectl describe pod kafka-0 -n confluent-kafka

# 查看日志
kubectl logs kafka-0 -n confluent-kafka
```

**问题**: LoadBalancer IP未分配
```bash
# 检查服务状态
kubectl get svc kafka-external-ssl -n confluent-kafka

# 检查云提供商配置
kubectl describe svc kafka-external-ssl -n confluent-kafka
```

### 3. 验证相关问题
**问题**: mTLS连接失败
```bash
# 检查证书挂载
kubectl exec kafka-0 -n confluent-kafka -- ls -la /opt/kafka/config/ssl/

# 检查SSL配置
kubectl exec kafka-0 -n confluent-kafka -- cat /opt/kafka/config/server.properties | grep ssl
```

## 📝 日志和报告

### 日志文件位置
- 部署日志: `/tmp/kafka-mtls-deployment-YYYYMMDD-HHMMSS.log`
- 验证报告: `./kafka-verification-report-YYYYMMDD-HHMMSS.txt`

### 日志级别
- `[INFO]`: 一般信息
- `[SUCCESS]`: 成功操作
- `[WARNING]`: 警告信息
- `[ERROR]`: 错误信息

## 🔗 相关文档

- [主配置文件说明](../README.md)
- [Kafka配置详情](../kafka-statefulset-ha-mtls.yaml)
- [服务配置说明](../kafka-service-mtls.yaml)
- [客户端配置](../kafka-client-mtls-config.yaml) 