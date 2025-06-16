#!/bin/bash

# Loki Demo环境部署脚本
# 使用方法: ./deploy-loki-demo.sh

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置变量
NAMESPACE="grafana-stack"

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
    log_info "检查Demo环境前置条件..."
    
    # 检查kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl未安装"
        exit 1
    fi
    
    # 检查集群连接
    if ! kubectl cluster-info &> /dev/null; then
        log_error "无法连接到Kubernetes集群"
        exit 1
    fi
    
    log_success "前置条件检查通过"
}

# 清理旧的部署
cleanup_existing() {
    log_info "清理现有Loki部署..."
    
    # 删除现有资源
    kubectl delete deployment loki -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    kubectl delete configmap loki-config -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    kubectl delete configmap loki-runtime-config -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    kubectl delete hpa loki-hpa -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    kubectl delete pdb loki-pdb -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    kubectl delete servicemonitor loki-metrics -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    kubectl delete prometheusrule loki-alerts -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    kubectl delete pvc loki-storage-pvc -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    kubectl delete pvc loki-wal-pvc -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true
    
    # 等待资源清理完成
    sleep 10
    
    log_success "现有部署清理完成"
}

# 验证Demo配置
validate_demo_config() {
    log_info "验证Demo环境配置..."
    
    # 检查必需的Demo配置文件
    REQUIRED_FILES=(
        "loki-configmap-demo.yaml"
        "loki-deployment-demo.yaml"
        "loki-serviceaccount.yaml"
    )
    
    for file in "${REQUIRED_FILES[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "缺少Demo环境配置文件: $file"
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
    
    log_success "Demo环境配置验证通过"
}

# 部署Demo环境
deploy_loki_demo() {
    log_info "开始部署Demo环境Loki..."
    
    # 1. 创建namespace（如果不存在）
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # 2. 部署ServiceAccount
    log_info "部署ServiceAccount..."
    kubectl apply -f loki-serviceaccount.yaml
    
    # 3. 部署配置
    log_info "部署Loki配置..."
    kubectl apply -f loki-configmap-demo.yaml
    
    # 4. 部署Loki
    log_info "部署Loki Deployment..."
    kubectl apply -f loki-deployment-demo.yaml
    
    log_success "Loki Demo环境部署完成"
}

# 等待部署就绪
wait_for_ready() {
    log_info "等待Loki Pod就绪..."
    
    # 等待Pod就绪
    kubectl wait --for=condition=ready pod -l app=loki -n "$NAMESPACE" --timeout=300s
    
    log_success "Loki Pod已就绪"
}

# 验证部署
verify_deployment() {
    log_info "验证Demo环境部署..."
    
    # 检查Pod状态
    log_info "Pod状态:"
    kubectl get pods -l app=loki -n "$NAMESPACE" -o wide
    
    # 检查服务状态
    log_info "服务状态:"
    kubectl get svc -l app=loki -n "$NAMESPACE"
    
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

# Demo环境使用说明
demo_usage() {
    log_info "Demo环境使用说明:"
    echo
    echo "🎯 Demo环境特性:"
    echo "  - 单副本部署 (1个Pod)"
    echo "  - 较小资源配置 (500m CPU, 1GB内存)"
    echo "  - 无认证模式 (auth_enabled: false)"
    echo "  - emptyDir存储 (非持久化)"
    echo "  - 20MB/s写入限制"
    echo
    echo "📊 访问方式:"
    echo "  kubectl port-forward svc/loki 3100:3100 -n $NAMESPACE"
    echo "  curl http://localhost:3100/ready"
    echo "  curl http://localhost:3100/metrics"
    echo
    echo "🔍 日志查看:"
    echo "  kubectl logs -f deployment/loki -n $NAMESPACE"
    echo
    echo "🗑️ 清理Demo环境:"
    echo "  kubectl delete namespace $NAMESPACE"
    echo
    echo "⚠️  注意: Demo环境使用emptyDir存储，Pod重启会丢失数据"
}

# 主函数
main() {
    echo "========================================"
    echo "    Loki Demo环境部署脚本"
    echo "========================================"
    echo
    
    check_prerequisites
    validate_demo_config
    
    # 确认部署
    log_warn "即将部署Demo环境Loki，这将:"
    echo "  - 清理现有的Loki部署"
    echo "  - 部署单副本Demo配置"
    echo "  - 使用临时存储(非持久化)"
    echo "  - 使用较小的资源配置"
    echo
    read -p "确认继续部署Demo环境？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "部署已取消"
        exit 1
    fi
    
    cleanup_existing
    deploy_loki_demo
    wait_for_ready
    verify_deployment
    demo_usage
    
    log_success "Loki Demo环境部署成功完成!"
}

# 错误处理
trap 'log_error "部署过程中发生错误，请检查上述输出"' ERR

# 执行主函数
main "$@" 