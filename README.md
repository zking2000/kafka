# Confluent Kafka on GKE with mTLS 部署指南

## 概述
本项目提供在Google Kubernetes Engine (GKE)上部署Confluent Kafka和Zookeeper的完整配置，并启用客户端mTLS验证。包含Terraform脚本用于自动创建GKE集群。

## 🏗️ 项目结构
```
kafka/
├── terraform/                  # Terraform配置文件
│   ├── main.tf                 # 主要资源定义
│   ├── variables.tf            # 变量定义
│   ├── outputs.tf              # 输出变量
│   ├── versions.tf             # 版本约束
│   ├── terraform.tfvars.example # 示例变量文件
│   └── README.md               # Terraform使用说明
├── scripts/                    # 自动化脚本
│   ├── check-environment.sh    # 环境检查
│   ├── create-gke-cluster.sh   # 创建GKE集群
│   ├── generate-ca.sh          # 生成CA证书
│   ├── deploy.sh               # 部署Kafka
│   └── test-kafka.sh           # 测试连接
├── *.yaml                      # Kubernetes配置文件
├── README.md                   # 本文档
└── TROUBLESHOOTING.md          # 故障排除指南
```

## 前置要求

### 🛠️ 工具安装
- **Terraform** >= 1.0
- **Google Cloud SDK** (gcloud)
- **kubectl**
- **Helm 3.x**

### ☁️ GCP准备
- GCP项目已创建
- 已启用计费
- 具有必要的IAM权限

## 🚀 快速开始

### 步骤0: 环境检查（推荐）

```bash
# 检查环境是否就绪
./scripts/check-environment.sh YOUR_PROJECT_ID
```

### 步骤1: 创建GKE集群

```bash
# 使用Terraform一键创建GKE集群
./scripts/create-gke-cluster.sh YOUR_PROJECT_ID
```

或者手动使用Terraform：

```bash
# 进入terraform目录
cd terraform

# 复制并编辑变量文件
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # 修改project_id等配置

# 初始化并部署
terraform init
terraform plan
terraform apply
```

### 步骤2: 生成CA证书

```bash
# 生成CA证书
./scripts/generate-ca.sh

# 更新ca-issuer.yaml文件中的证书内容
```

### 步骤3: 部署Kafka和Zookeeper

```bash
# 一键部署
./scripts/deploy.sh
```

### 步骤4: 测试连接

```bash
# 测试mTLS连接
./scripts/test-kafka.sh
```

## 📋 详细部署步骤

### 1. 创建GKE集群 (使用Terraform)

#### 自动化方式
```bash
./scripts/create-gke-cluster.sh YOUR_PROJECT_ID
```

#### 手动方式
```bash
cd terraform

# 配置变量
cp terraform.tfvars.example terraform.tfvars
# 编辑terraform.tfvars，设置project_id等参数

# 部署集群
terraform init
terraform plan
terraform apply

# 配置kubectl
gcloud container clusters get-credentials kafka-cluster \
  --region europe-west2 --project YOUR_PROJECT_ID
```

### 2. 创建命名空间
```bash
kubectl apply -f namespace.yaml
```

### 3. 安装cert-manager (如果未安装)
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
```

### 4. 创建证书颁发机构
```bash
# 生成CA证书
./scripts/generate-ca.sh

# 应用证书配置
kubectl apply -f ca-issuer.yaml
kubectl apply -f certificates.yaml
```

### 5. 部署Zookeeper
```bash
kubectl apply -f zookeeper-config.yaml
kubectl apply -f zookeeper-deployment.yaml
kubectl apply -f zookeeper-service.yaml
```

### 6. 部署Kafka
```bash
kubectl apply -f kafka-config.yaml
kubectl apply -f kafka-deployment.yaml
kubectl apply -f kafka-service.yaml
```

### 7. 部署客户端示例
```bash
kubectl apply -f client-example.yaml
```

### 8. 验证部署
```bash
kubectl get pods -n kafka
kubectl get services -n kafka
kubectl get certificates -n kafka
```

## 🔐 mTLS配置说明
- 使用cert-manager自动生成和管理证书
- 客户端和服务器都需要有效的证书
- 证书存储在Kubernetes Secrets中
- 支持证书自动轮换

## 📊 监控和日志
- 配置了Prometheus监控端点
- 日志输出到stdout，可通过kubectl logs查看
- JMX指标可通过端口转发访问

## 🛠️ 运维操作

### 查看集群状态
```bash
# 查看所有资源
kubectl get all -n kafka

# 查看证书状态
kubectl get certificates -n kafka

# 查看日志
kubectl logs -f kafka-0 -n kafka
kubectl logs -f zookeeper-0 -n kafka
```

### 扩缩容操作
```bash
# 扩展Kafka节点
kubectl scale statefulset kafka --replicas=3 -n kafka

# 扩展Zookeeper节点
kubectl scale statefulset zookeeper --replicas=3 -n kafka
```

### 证书轮换
```bash
# 手动触发证书轮换
kubectl delete certificate kafka-server-cert -n kafka
kubectl apply -f certificates.yaml

# 重启服务以加载新证书
kubectl rollout restart statefulset kafka -n kafka
```

## 💰 成本优化

### Terraform配置优化
```hcl
# 使用抢占式实例节省成本
preemptible = true

# 调整机器类型
machine_type = "e2-medium"

# 启用自动扩缩容
min_node_count = 0
max_node_count = 10
```

### 资源限制调整
```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "500m"
```

## 🔧 故障排除
详细的故障排除指南请参考 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

常用调试命令：
- 检查pod状态: `kubectl describe pod <pod-name> -n kafka`
- 查看日志: `kubectl logs <pod-name> -n kafka`
- 验证证书: `kubectl get certificates -n kafka`
- 测试连接: `kubectl exec -it kafka-client -n kafka -- kafka-topics --bootstrap-server kafka-service:9093 --list --command-config /etc/kafka/client.properties`

## 🧹 清理资源

### 清理Kafka部署
```bash
kubectl delete namespace kafka
```

### 清理GKE集群
```bash
cd terraform
terraform destroy
```

## 📚 相关文档
- [Terraform配置说明](terraform/README.md)
- [故障排除指南](TROUBLESHOOTING.md)
- [Confluent Platform文档](https://docs.confluent.io/)
- [GKE官方文档](https://cloud.google.com/kubernetes-engine/docs)

## 🤝 贡献
欢迎提交Issue和Pull Request来改进这个项目！ 