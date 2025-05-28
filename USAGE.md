# 使用指南

## 🚀 快速开始

### 步骤1: 准备GCP环境

1. **创建或选择GCP项目**：
   ```bash
   # 列出现有项目
   gcloud projects list
   
   # 或创建新项目
   gcloud projects create YOUR-PROJECT-ID --name="Kafka Cluster"
   ```

2. **设置计费账户**（必需）：
   - 在GCP控制台中为项目启用计费
   - 或使用命令行：`gcloud billing projects link YOUR-PROJECT-ID --billing-account=BILLING-ACCOUNT-ID`

3. **验证权限**：
   ```bash
   # 检查当前用户
   gcloud auth list
   
   # 检查项目权限
   gcloud projects get-iam-policy YOUR-PROJECT-ID
   ```

### 步骤2: 创建GKE集群

```bash
# 确保在项目根目录
cd /path/to/kafka

# 运行创建脚本
./scripts/create-gke-cluster.sh YOUR-PROJECT-ID
```

### 步骤3: 部署Kafka

```bash
# 生成CA证书
./scripts/generate-ca.sh

# 更新ca-issuer.yaml中的证书内容（脚本会提示）

# 部署Kafka和Zookeeper
./scripts/deploy.sh

# 测试连接
./scripts/test-kafka.sh
```

## 🔧 故障排除

### 常见错误及解决方案

#### 1. "terraform目录不存在"
**原因**: 不在正确的项目根目录
**解决**: 
```bash
# 确保在包含terraform目录的根目录
ls -la  # 应该看到terraform/目录
pwd     # 确认当前路径
```

#### 2. "Permission denied to enable service"
**原因**: 没有项目权限或项目不存在
**解决**:
```bash
# 检查项目是否存在
gcloud projects describe YOUR-PROJECT-ID

# 检查权限
gcloud projects get-iam-policy YOUR-PROJECT-ID

# 如果需要，请项目管理员添加以下角色：
# - Project Editor 或
# - Compute Admin + Container Admin + Service Usage Admin
```

#### 3. "未登录GCP"
**解决**:
```bash
gcloud auth login
gcloud auth application-default login
```

#### 4. "kubectl未安装"
**解决**:
```bash
# macOS
brew install kubectl

# 或通过gcloud安装
gcloud components install kubectl
```

#### 5. "terraform未安装"
**解决**:
```bash
# macOS
brew install terraform

# 或下载: https://www.terraform.io/downloads.html
```

## 📋 完整示例

假设您的项目ID是 `my-kafka-project-123`：

```bash
# 1. 克隆或下载项目代码
cd ~/workspace/kafka

# 2. 验证目录结构
ls -la
# 应该看到: terraform/ scripts/ *.yaml 等文件

# 3. 登录GCP
gcloud auth login
gcloud auth application-default login

# 4. 设置项目
gcloud config set project my-kafka-project-123

# 5. 创建GKE集群
./scripts/create-gke-cluster.sh my-kafka-project-123

# 6. 生成证书
./scripts/generate-ca.sh

# 7. 编辑ca-issuer.yaml，更新证书内容

# 8. 部署Kafka
./scripts/deploy.sh

# 9. 测试
./scripts/test-kafka.sh
```

## 🎯 手动部署（如果脚本失败）

如果自动化脚本遇到问题，您可以手动执行：

### 1. 手动创建GKE集群

```bash
cd terraform

# 复制配置文件
cp terraform.tfvars.example terraform.tfvars

# 编辑配置
vim terraform.tfvars
# 修改: project_id = "your-real-project-id"

# 初始化和部署
terraform init
terraform plan
terraform apply

# 配置kubectl
gcloud container clusters get-credentials kafka-cluster \
  --region europe-west2 --project your-real-project-id
```

### 2. 手动部署Kafka

```bash
cd ..  # 回到项目根目录

# 按顺序执行
kubectl apply -f namespace.yaml
kubectl apply -f ca-issuer.yaml
kubectl apply -f certificates.yaml
kubectl apply -f zookeeper-config.yaml
kubectl apply -f zookeeper-deployment.yaml
kubectl apply -f zookeeper-service.yaml
kubectl apply -f kafka-config.yaml
kubectl apply -f kafka-deployment.yaml
kubectl apply -f kafka-service.yaml
kubectl apply -f client-example.yaml
```

## 💡 提示

1. **项目ID要求**：
   - 必须是真实存在的GCP项目
   - 您必须有该项目的编辑权限
   - 项目必须启用计费

2. **区域选择**：
   - 默认使用 `europe-west2` (伦敦)
   - 可在 `terraform.tfvars` 中修改

3. **成本控制**：
   - 使用 `preemptible = true` 节省成本
   - 调整 `machine_type` 和节点数量
   - 设置 `min_node_count = 0` 实现自动缩容

4. **安全性**：
   - 所有通信都使用mTLS加密
   - 私有集群配置
   - 网络策略隔离 