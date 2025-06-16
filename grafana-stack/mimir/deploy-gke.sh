#!/bin/bash

# Mimir GKE Demo 环境部署脚本
# 使用GCS作为后端存储，24小时数据保留策略

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Mimir GKE Demo 部署脚本 ===${NC}"

# 检查必要的命令
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}错误: $1 命令未找到，请先安装${NC}"
        exit 1
    fi
}

echo -e "${YELLOW}检查必要的工具...${NC}"
check_command kubectl
check_command gcloud

# 设置变量（用户需要修改这些值）
PROJECT_ID=${PROJECT_ID:-"your-project-id"}
CLUSTER_NAME=${CLUSTER_NAME:-"mimir-demo-cluster"}
ZONE=${ZONE:-"us-central1-a"}
BUCKET_NAME=${BUCKET_NAME:-"mimir-demo-bucket"}

echo -e "${YELLOW}请确认以下配置:${NC}"
echo "GCP Project ID: $PROJECT_ID"
echo "GKE Cluster: $CLUSTER_NAME"
echo "Zone: $ZONE"
echo "GCS Bucket: $BUCKET_NAME"
echo ""

read -p "是否继续部署? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "部署已取消"
    exit 1
fi

# 1. 设置 GCP 项目
echo -e "${GREEN}步骤 1: 设置 GCP 项目${NC}"
gcloud config set project $PROJECT_ID

# 2. 获取 GKE 集群凭据
echo -e "${GREEN}步骤 2: 获取 GKE 集群凭据${NC}"
gcloud container clusters get-credentials $CLUSTER_NAME --zone $ZONE

# 3. 创建 GCS bucket（如果不存在）
echo -e "${GREEN}步骤 3: 创建 GCS bucket${NC}"
if ! gsutil ls gs://$BUCKET_NAME &> /dev/null; then
    gsutil mb gs://$BUCKET_NAME
    echo "已创建 GCS bucket: $BUCKET_NAME"
else
    echo "GCS bucket $BUCKET_NAME 已存在"
fi

# 4. 创建 Google 服务账号
echo -e "${GREEN}步骤 4: 创建 Google 服务账号${NC}"
SA_NAME="mimir-demo"
SA_EMAIL="$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"

if ! gcloud iam service-accounts describe $SA_EMAIL &> /dev/null; then
    gcloud iam service-accounts create $SA_NAME \
        --display-name="Mimir Demo Service Account"
    
    # 授予 GCS 权限
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:$SA_EMAIL" \
        --role="roles/storage.objectAdmin"
    
    echo "已创建服务账号: $SA_EMAIL"
else
    echo "服务账号 $SA_EMAIL 已存在"
fi

# 5. 启用 Workload Identity
echo -e "${GREEN}步骤 5: 配置 Workload Identity${NC}"
gcloud iam service-accounts add-iam-policy-binding $SA_EMAIL \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:$PROJECT_ID.svc.id.goog[mimir-demo/mimir-service-account]"

# 6. 更新配置文件中的 bucket 名称
echo -e "${GREEN}步骤 6: 更新配置文件${NC}"
sed -i.bak "s/mimir-demo-bucket/$BUCKET_NAME/g" k8s-configmap.yaml
sed -i.bak "s/PROJECT_ID/$PROJECT_ID/g" k8s-serviceaccount.yaml

# 7. 部署到 Kubernetes
echo -e "${GREEN}步骤 7: 部署到 Kubernetes${NC}"
kubectl apply -f k8s-namespace.yaml
kubectl apply -f k8s-serviceaccount.yaml
kubectl apply -f k8s-configmap.yaml
kubectl apply -f k8s-memcached.yaml
kubectl apply -f k8s-mimir.yaml
kubectl apply -f k8s-prometheus.yaml
kubectl apply -f k8s-grafana.yaml

# 8. 等待服务启动
echo -e "${GREEN}步骤 8: 等待服务启动${NC}"
echo "等待 Pod 启动..."
kubectl wait --namespace=mimir-demo --for=condition=Ready pod --selector=app=mimir --timeout=300s
kubectl wait --namespace=mimir-demo --for=condition=Ready pod --selector=app=memcached --timeout=300s
kubectl wait --namespace=mimir-demo --for=condition=Ready pod --selector=app=prometheus --timeout=300s
kubectl wait --namespace=mimir-demo --for=condition=Ready pod --selector=app=grafana --timeout=300s

# 9. 显示访问信息
echo -e "${GREEN}步骤 9: 获取访问信息${NC}"

# 获取 Grafana LoadBalancer IP
echo "等待 Grafana LoadBalancer IP..."
GRAFANA_IP=""
while [ -z $GRAFANA_IP ]; do
    GRAFANA_IP=$(kubectl get service grafana -n mimir-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [ -z $GRAFANA_IP ]; then
        echo "等待 LoadBalancer IP 分配..."
        sleep 10
    fi
done

echo -e "${GREEN}=== 部署完成! ===${NC}"
echo ""
echo "服务访问信息:"
echo "- Grafana: http://$GRAFANA_IP:3000 (admin/admin)"
echo "- Mimir API: kubectl port-forward -n mimir-demo svc/mimir 8080:8080"
echo "- Prometheus: kubectl port-forward -n mimir-demo svc/prometheus 9090:9090"
echo ""
echo "使用以下命令查看 Pod 状态:"
echo "kubectl get pods -n mimir-demo"
echo ""
echo "查看 Mimir 日志:"
echo "kubectl logs -n mimir-demo -l app=mimir"
echo ""
echo -e "${YELLOW}注意: 数据将在 24 小时后自动删除${NC}"

# 恢复配置文件备份
mv k8s-configmap.yaml.bak k8s-configmap.yaml
mv k8s-serviceaccount.yaml.bak k8s-serviceaccount.yaml 