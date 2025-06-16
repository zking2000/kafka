#!/bin/bash

# Workload Identity 设置脚本
# 此脚本用于配置GKE Workload Identity以访问GCS

set -e

echo "🔐 设置 Workload Identity 用于 Loki GCS 访问..."

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 函数：打印带颜色的消息
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# 检查必需的环境变量
if [ -z "$PROJECT_ID" ]; then
    print_message $RED "❌ 请设置 PROJECT_ID 环境变量"
    echo "例如: export PROJECT_ID=your-gcp-project-id"
    exit 1
fi

if [ -z "$GSA_NAME" ]; then
    GSA_NAME="loki-storage"
    print_message $YELLOW "⚠️  使用默认的Google服务账号名称: $GSA_NAME"
fi

if [ -z "$CLUSTER_NAME" ]; then
    print_message $RED "❌ 请设置 CLUSTER_NAME 环境变量"
    echo "例如: export CLUSTER_NAME=your-gke-cluster-name"
    exit 1
fi

if [ -z "$CLUSTER_ZONE" ]; then
    print_message $RED "❌ 请设置 CLUSTER_ZONE 环境变量"
    echo "例如: export CLUSTER_ZONE=us-central1-a"
    exit 1
fi

BUCKET_NAME="loki_44084750"
KSA_NAME="loki-gcs"
NAMESPACE="grafana-stack"

print_message $BLUE "配置信息："
echo "- GCP项目ID: $PROJECT_ID"
echo "- Google服务账号: $GSA_NAME@$PROJECT_ID.iam.gserviceaccount.com"
echo "- GKE集群: $CLUSTER_NAME ($CLUSTER_ZONE)"
echo "- K8s服务账号: $KSA_NAME"
echo "- Namespace: $NAMESPACE"
echo "- GCS存储桶: $BUCKET_NAME"
echo ""

# 1. 创建Google服务账号（如果不存在）
print_message $BLUE "1. 创建Google服务账号..."
if gcloud iam service-accounts describe $GSA_NAME@$PROJECT_ID.iam.gserviceaccount.com --project=$PROJECT_ID &>/dev/null; then
    print_message $YELLOW "⚠️  Google服务账号已存在"
else
    gcloud iam service-accounts create $GSA_NAME \
        --display-name="Loki GCS Storage Service Account" \
        --project=$PROJECT_ID
    print_message $GREEN "✅ Google服务账号已创建"
fi

# 2. 为Google服务账号授予GCS权限
print_message $BLUE "2. 授予GCS存储权限..."
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$GSA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/storage.objectAdmin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$GSA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/storage.legacyBucketReader"

print_message $GREEN "✅ GCS权限已授予"

# 3. 确保集群启用了Workload Identity
print_message $BLUE "3. 检查Workload Identity状态..."
WI_STATUS=$(gcloud container clusters describe $CLUSTER_NAME \
    --zone=$CLUSTER_ZONE \
    --project=$PROJECT_ID \
    --format="value(workloadIdentityConfig.workloadPool)" 2>/dev/null || echo "")

if [ -z "$WI_STATUS" ]; then
    print_message $YELLOW "⚠️  集群未启用Workload Identity，正在启用..."
    gcloud container clusters update $CLUSTER_NAME \
        --zone=$CLUSTER_ZONE \
        --workload-pool=$PROJECT_ID.svc.id.goog \
        --project=$PROJECT_ID
    print_message $GREEN "✅ Workload Identity已启用"
else
    print_message $GREEN "✅ Workload Identity已启用"
fi

# 4. 更新ServiceAccount配置文件
print_message $BLUE "4. 更新Kubernetes ServiceAccount配置..."
sed -i.bak "s/PROJECT-ID/$PROJECT_ID/g; s/GSA-NAME/$GSA_NAME/g" loki-serviceaccount.yaml
print_message $GREEN "✅ ServiceAccount配置已更新"

# 5. 创建Kubernetes资源
print_message $BLUE "5. 部署Kubernetes ServiceAccount..."
kubectl apply -f loki-serviceaccount.yaml
print_message $GREEN "✅ Kubernetes ServiceAccount已创建"

# 6. 配置IAM策略绑定
print_message $BLUE "6. 配置Workload Identity IAM绑定..."
gcloud iam service-accounts add-iam-policy-binding \
    $GSA_NAME@$PROJECT_ID.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:$PROJECT_ID.svc.id.goog[$NAMESPACE/$KSA_NAME]" \
    --project=$PROJECT_ID

print_message $GREEN "✅ Workload Identity IAM绑定已配置"

# 7. 验证配置
print_message $BLUE "7. 验证Workload Identity配置..."
kubectl annotate serviceaccount $KSA_NAME \
    -n $NAMESPACE \
    iam.gke.io/gcp-service-account=$GSA_NAME@$PROJECT_ID.iam.gserviceaccount.com \
    --overwrite

print_message $GREEN "🎉 Workload Identity设置完成！"

echo ""
print_message $BLUE "📋 后续步骤："
echo "1. 运行验证脚本: ./verify-loki-config.sh"
echo "2. 部署Loki: ./deploy-loki.sh"
echo "3. 验证Loki Pod可以访问GCS存储桶"

echo ""
print_message $YELLOW "💡 如需测试GCS访问权限，可以运行："
echo "kubectl run -it --rm debug --image=google/cloud-sdk:slim --restart=Never --serviceaccount=$KSA_NAME -n $NAMESPACE -- gsutil ls gs://$BUCKET_NAME" 