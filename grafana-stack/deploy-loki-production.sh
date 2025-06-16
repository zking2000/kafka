#!/bin/bash

# Loki生产环境部署脚本
# 使用方法: ./deploy-loki-production.sh

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
NAMESPACE="grafana-stack"
CLUSTER_NAME="kafka-cluster"
REGION="europe-west2"
PROJECT_ID="coral-pipe-457011-d2"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 检查前置条件
check_prerequisites() {
    log_info "检查生产环境前置条件..."
    
    # 检查kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl未安装"
        exit 1
    fi
    
    # 检查gcloud
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI未安装"
        exit 1
    fi
    
    # 检查集群连接
    if ! kubectl cluster-info &> /dev/null; then
        log_error "无法连接到Kubernetes集群"
        exit 1
    fi
    
    # 检查当前集群是否为生产集群
    CURRENT_CLUSTER=$(kubectl config current-context)
    if [[ ! "$CURRENT_CLUSTER" =~ "$CLUSTER_NAME" ]]; then
        log_warn "当前集群: $CURRENT_CLUSTER"
        log_warn "这看起来不是生产集群！"
        read -p "确认要在当前集群部署生产环境Loki吗？(y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "部署已取消"
            exit 1
        fi
    fi
    
    log_success "前置条件检查通过"
}

# 备份现有配置
backup_existing() {
    log_info "备份现有配置..."
    
    BACKUP_DIR="backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # 备份现有资源
    kubectl get deployment loki -n "$NAMESPACE" -o yaml > "$BACKUP_DIR/loki-deployment.yaml" 2>/dev/null || true
    kubectl get configmap loki-config -n "$NAMESPACE" -o yaml > "$BACKUP_DIR/loki-configmap.yaml" 2>/dev/null || true
    kubectl get hpa loki-hpa -n "$NAMESPACE" -o yaml > "$BACKUP_DIR/loki-hpa.yaml" 2>/dev/null || true
    
    log_success "配置已备份到 $BACKUP_DIR/"
}

# 验证生产环境配置
validate_production_config() {
    log_info "验证生产环境配置..."
    
    # 检查必需的生产配置文件
    REQUIRED_FILES=(
        "loki-configmap-production.yaml"
        "loki-deployment-production.yaml" 
        "loki-hpa-production.yaml"
        "loki-monitoring-production.yaml"
        "loki-serviceaccount.yaml"
    )
    
    for file in "${REQUIRED_FILES[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "缺少生产环境配置文件: $file"
            exit 1
        fi
    done
    
    # 验证配置语法
    for file in "${REQUIRED_FILES[@]}"; do
        if ! kubectl apply --dry-run=client -f "$file" &>/dev/null; then
            log_error "配置文件语法错误: $file"
            exit 1
        fi
    done
    
    log_success "生产环境配置验证通过"
}

# 部署网络策略
deploy_network_policies() {
    log_info "部署网络策略..."
    
    cat <<EOF | kubectl apply -f -
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: loki-network-policy
  namespace: $NAMESPACE
spec:
  podSelector:
    matchLabels:
      app: loki
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # 允许Prometheus抓取指标
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    ports:
    - protocol: TCP
      port: 3100
  # 允许Grafana查询
  - from:
    - podSelector:
        matchLabels:
          app: grafana
    ports:
    - protocol: TCP
      port: 3100
  # 允许应用发送日志
  - from:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 3100
  egress:
  # 允许访问GCS
  - to: []
    ports:
    - protocol: TCP
      port: 443
  # 允许DNS解析
  - to: []
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
  # 允许集群内通信
  - to:
    - podSelector:
        matchLabels:
          app: loki
    ports:
    - protocol: TCP
      port: 9095
EOF
    
    log_success "网络策略部署完成"
}

# 执行部署
deploy_loki() {
    log_info "开始部署生产环境Loki..."
    
    # 1. 创建namespace（如果不存在）
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # 2. 部署ServiceAccount和Workload Identity
    log_info "部署ServiceAccount和Workload Identity..."
    kubectl apply -f loki-serviceaccount.yaml
    
    # 3. 部署存储类和PVC
    log_info "部署存储配置..."
    kubectl apply -f loki-deployment-production.yaml
    
    # 等待PVC绑定
    log_info "等待PVC绑定..."
    kubectl wait --for=condition=Bound pvc/loki-storage-pvc -n "$NAMESPACE" --timeout=300s
    kubectl wait --for=condition=Bound pvc/loki-wal-pvc -n "$NAMESPACE" --timeout=300s
    
    # 4. 部署配置
    log_info "部署Loki配置..."
    kubectl apply -f loki-configmap-production.yaml
    
    # 5. 部署Loki
    log_info "部署Loki Deployment..."
    kubectl apply -f loki-deployment-production.yaml
    
    # 6. 部署HPA和PDB
    log_info "部署自动伸缩配置..."
    kubectl apply -f loki-hpa-production.yaml
    
    # 7. 部署监控配置
    log_info "部署监控配置..."
    kubectl apply -f loki-monitoring-production.yaml
    
    # 8. 部署网络策略
    deploy_network_policies
    
    log_success "Loki生产环境部署完成"
}

# 等待部署就绪
wait_for_ready() {
    log_info "等待Loki Pod就绪..."
    
    # 等待Pod就绪
    kubectl wait --for=condition=ready pod -l app=loki -n "$NAMESPACE" --timeout=600s
    
    # 检查副本数
    READY_REPLICAS=$(kubectl get deployment loki -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    DESIRED_REPLICAS=$(kubectl get deployment loki -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
    
    log_info "就绪副本数: $READY_REPLICAS/$DESIRED_REPLICAS"
    
    if [[ "$READY_REPLICAS" == "$DESIRED_REPLICAS" ]]; then
        log_success "所有Loki Pod已就绪"
    else
        log_warn "部分Pod尚未就绪，请检查Pod状态"
    fi
}

# 验证部署
verify_deployment() {
    log_info "验证生产环境部署..."
    
    # 检查Pod状态
    log_info "Pod状态:"
    kubectl get pods -l app=loki -n "$NAMESPACE" -o wide
    
    # 检查服务状态
    log_info "服务状态:"
    kubectl get svc -l app=loki -n "$NAMESPACE"
    
    # 检查HPA状态
    log_info "HPA状态:"
    kubectl get hpa loki-hpa -n "$NAMESPACE"
    
    # 检查PVC状态
    log_info "存储状态:"
    kubectl get pvc -l app=loki -n "$NAMESPACE"
    
    # 健康检查
    log_info "执行健康检查..."
    kubectl port-forward svc/loki 3100:3100 -n "$NAMESPACE" &
    PORT_FORWARD_PID=$!
    
    sleep 5
    
    if curl -s http://localhost:3100/ready &>/dev/null; then
        log_success "Loki健康检查通过"
    else
        log_warn "Loki健康检查失败，请检查日志"
    fi
    
    kill $PORT_FORWARD_PID 2>/dev/null || true
    
    # 检查日志
    log_info "最近日志:"
    kubectl logs -l app=loki -n "$NAMESPACE" --tail=10
}

# 生产环境优化建议
production_recommendations() {
    log_info "生产环境优化建议:"
    echo
    echo "1. 监控和告警:"
    echo "   - 已部署Prometheus监控规则"
    echo "   - 建议配置AlertManager通知"
    echo "   - 监控GCS存储使用情况"
    echo
    echo "2. 安全配置:"
    echo "   - 已启用多租户认证"
    echo "   - 已配置网络策略"
    echo "   - 建议定期更新镜像"
    echo
    echo "3. 性能优化:"
    echo "   - 当前配置50MB/s写入限制"
    echo "   - 可根据实际负载调整HPA阈值"
    echo "   - 建议监控GCS API配额"
    echo
    echo "4. 数据管理:"
    echo "   - 已启用数据压缩和保留策略"
    echo "   - 建议配置备份策略"
    echo "   - 监控存储成本"
    echo
    echo "5. 运维操作:"
    echo "   - 使用 kubectl logs -f deployment/loki -n $NAMESPACE 查看日志"
    echo "   - 使用 kubectl exec -it deployment/loki -n $NAMESPACE -- /bin/sh 进入容器"
    echo "   - 监控面板: Grafana -> Loki生产环境监控"
}

# 主函数
main() {
    echo "========================================"
    echo "    Loki 生产环境部署脚本"
    echo "========================================"
    echo
    
    check_prerequisites
    backup_existing
    validate_production_config
    
    # 最终确认
    log_warn "即将在生产环境部署Loki，这将:"
    echo "  - 使用生产级配置和资源限制"
    echo "  - 启用多租户认证和网络策略"
    echo "  - 配置自动伸缩和监控告警"
    echo "  - 使用持久化存储和GCS对象存储"
    echo
    read -p "确认继续部署？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "部署已取消"
        exit 1
    fi
    
    deploy_loki
    wait_for_ready
    verify_deployment
    production_recommendations
    
    log_success "Loki生产环境部署成功完成!"
}

# 错误处理
trap 'log_error "部署过程中发生错误，请检查上述输出"' ERR

# 执行主函数
main "$@" 