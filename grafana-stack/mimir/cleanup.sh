#!/bin/bash

# Mimir GKE Demo 环境清理脚本

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}=== Mimir GKE Demo 环境清理脚本 ===${NC}"

# 设置变量
PROJECT_ID=${PROJECT_ID:-"your-project-id"}
BUCKET_NAME=${BUCKET_NAME:-"mimir-demo-bucket"}

echo -e "${YELLOW}即将删除以下资源:${NC}"
echo "- Kubernetes 命名空间: mimir-demo"
echo "- Google 服务账号: mimir-demo@$PROJECT_ID.iam.gserviceaccount.com"
echo "- GCS Bucket: $BUCKET_NAME (可选)"
echo ""

read -p "确认删除? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "清理已取消"
    exit 1
fi

# 1. 删除 Kubernetes 资源
echo -e "${GREEN}步骤 1: 删除 Kubernetes 资源${NC}"
kubectl delete namespace mimir-demo --ignore-not-found=true

# 2. 删除 Google 服务账号
echo -e "${GREEN}步骤 2: 删除 Google 服务账号${NC}"
SA_EMAIL="mimir-demo@$PROJECT_ID.iam.gserviceaccount.com"
if gcloud iam service-accounts describe $SA_EMAIL &> /dev/null; then
    # 移除 IAM 绑定
    gcloud projects remove-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:$SA_EMAIL" \
        --role="roles/storage.objectAdmin" \
        --quiet || true
    
    # 删除服务账号
    gcloud iam service-accounts delete $SA_EMAIL --quiet
    echo "已删除服务账号: $SA_EMAIL"
else
    echo "服务账号 $SA_EMAIL 不存在"
fi

# 3. 询问是否删除 GCS bucket
echo -e "${YELLOW}是否删除 GCS bucket: $BUCKET_NAME?${NC}"
read -p "删除 bucket 将永久删除所有存储的数据 (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if gsutil ls gs://$BUCKET_NAME &> /dev/null; then
        gsutil rm -r gs://$BUCKET_NAME
        echo "已删除 GCS bucket: $BUCKET_NAME"
    else
        echo "GCS bucket $BUCKET_NAME 不存在"
    fi
else
    echo "保留 GCS bucket: $BUCKET_NAME"
fi

echo -e "${GREEN}=== 清理完成! ===${NC}"
echo "所有 Mimir demo 资源已删除" 