#!/bin/bash

# Loki部署脚本 - 针对速率优化
# 此脚本将部署优化的Loki配置以解决OpenTelemetry速率问题

set -e

echo "🚀 开始部署优化的Loki..."

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

# 检查kubectl连接
print_message $BLUE "检查Kubernetes连接..."
if ! kubectl cluster-info &> /dev/null; then
    print_message $RED "❌ 无法连接到Kubernetes集群"
    exit 1
fi
print_message $GREEN "✅ Kubernetes连接正常"

# 创建namespace（如果不存在）
print_message $BLUE "创建grafana-stack namespace..."
kubectl apply -f loki-namespace.yaml
print_message $GREEN "✅ Namespace已创建"

# 部署ConfigMaps
print_message $BLUE "部署Loki配置..."
kubectl apply -f loki-configmap.yaml
print_message $GREEN "✅ Loki配置已部署"

# 部署Loki
print_message $BLUE "部署Loki服务..."
kubectl apply -f loki-deployment.yaml
print_message $GREEN "✅ Loki服务已部署"

# 部署HPA和PDB
print_message $BLUE "部署自动伸缩配置..."
kubectl apply -f loki-hpa.yaml
print_message $GREEN "✅ 自动伸缩配置已部署"

# 部署监控
print_message $BLUE "部署监控配置..."
kubectl apply -f loki-servicemonitor.yaml
print_message $GREEN "✅ 监控配置已部署"

# 等待Loki Ready
print_message $BLUE "等待Loki启动..."
kubectl wait --namespace=grafana-stack \
    --for=condition=ready pod \
    --selector=app=loki \
    --timeout=300s

print_message $GREEN "✅ Loki已成功启动"

# 显示部署状态
print_message $BLUE "部署状态:"
kubectl get pods,svc,hpa -n grafana-stack -l app=loki

# 显示Loki服务信息
print_message $BLUE "Loki服务信息:"
echo "HTTP端点: kubectl port-forward -n grafana-stack svc/loki 3100:3100"
echo "GRPC端点: kubectl port-forward -n grafana-stack svc/loki 9095:9095"

# 显示配置优化信息
print_message $YELLOW "🔧 速率优化配置说明:"
echo "• 摄取速率限制: 50MB/s (突发100MB/s)"
echo "• 并发处理能力: 32个并发刷新"
echo "• 自动伸缩: 2-8个副本"
echo "• Chunk优化: 减少空闲时间和保留期"
echo "• WAL启用: 提高数据持久性"
echo "• 内存限制器: 防止OOM"

print_message $GREEN "🎉 Loki部署完成！"
print_message $YELLOW "💡 建议:"
echo "1. 监控Loki指标，确保摄取速率正常"
echo "2. 根据实际负载调整资源限制"
echo "3. 查看日志确认没有速率限制错误"
echo "4. 测试与OpenTelemetry的集成" 