#!/bin/bash

# mTLS Kafka 高可用集群统一部署脚本
# 整合了详细环境检查、交互式模式和完整的部署流程

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KAFKA_DIR="${SCRIPT_DIR}/.."
NAMESPACE="confluent-kafka"
LOG_FILE="/tmp/kafka-mtls-deployment-$(date +%Y%m%d-%H%M%S).log"

# 日志函数
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] 警告:${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] 错误:${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] 信息:${NC} $1" | tee -a "$LOG_FILE"
}

# 显示帮助信息
show_help() {
    cat << EOF
mTLS Kafka 高可用集群统一部署脚本

使用方法:
    $0 [命令] [选项]

命令:
    deploy      完整部署流程（默认）
    check       仅运行环境检查
    certs       仅生成证书
    kafka       仅部署Kafka集群
    verify      仅运行验证
    status      查看集群状态
    cleanup     清理集群
    help        显示帮助信息

选项:
    --skip-check        跳过环境检查
    --skip-certs        跳过证书生成（如果已存在）
    --skip-verify       跳过部署后验证
    --namespace NAME    指定命名空间（默认: confluent-kafka）
    --log-file FILE     指定日志文件路径
    --interactive       交互式模式

示例:
    $0 deploy                    # 完整部署
    $0 check                     # 仅检查环境
    $0 deploy --skip-check       # 跳过环境检查直接部署
    $0 deploy --interactive      # 交互式部署
    $0 cleanup                   # 清理集群

EOF
}

# 详细环境检查
check_environment() {
    log "🔍 开始详细环境检查..."
    
    local check_failed=false
    
    # 检查必要工具
    info "检查必要工具..."
    local tools=("kubectl" "openssl" "base64" "keytool")
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            log "✅ $tool 已安装"
        else
            error "❌ $tool 未找到，请先安装"
            check_failed=true
        fi
    done
    
    # 检查kubectl连接
    info "检查Kubernetes集群连接..."
    if kubectl cluster-info &> /dev/null; then
        log "✅ Kubernetes集群连接正常"
        
        # 显示集群信息
        local cluster_info=$(kubectl cluster-info | head -1)
        info "集群信息: $cluster_info"
        
        # 检查节点数量和资源
        local node_count=$(kubectl get nodes --no-headers | wc -l)
        info "集群节点数: $node_count"
        
        if [ "$node_count" -lt 3 ]; then
            warn "节点数量不足3个，建议至少3个节点以确保高可用性"
        fi
        
        # 检查节点资源
        info "检查节点资源..."
        kubectl get nodes -o custom-columns="NAME:.metadata.name,CPU:.status.capacity.cpu,MEMORY:.status.capacity.memory" | tee -a "$LOG_FILE"
        
    else
        error "❌ 无法连接到Kubernetes集群"
        error "请检查kubectl配置: kubectl config current-context"
        check_failed=true
    fi
    
    # 检查存储类
    info "检查存储类..."
    if kubectl get storageclass &> /dev/null; then
        log "✅ 存储类检查完成"
        kubectl get storageclass | tee -a "$LOG_FILE"
        
        # 检查是否有SSD存储类
        if kubectl get storageclass ssd &> /dev/null; then
            log "✅ SSD存储类已存在"
        else
            warn "SSD存储类不存在，将使用默认存储类"
            info "如需高性能，建议创建SSD存储类"
        fi
    else
        warn "无法获取存储类信息"
    fi
    
    # 检查LoadBalancer支持
    info "检查LoadBalancer支持..."
    local lb_services=$(kubectl get svc --all-namespaces -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].metadata.name}' | wc -w)
    if [ "$lb_services" -gt 0 ]; then
        log "✅ 集群支持LoadBalancer服务"
    else
        info "未发现LoadBalancer服务，这在某些环境中是正常的"
    fi
    
    # 检查RBAC权限
    info "检查RBAC权限..."
    if kubectl auth can-i create pods --namespace="$NAMESPACE" &> /dev/null; then
        log "✅ 具有必要的RBAC权限"
    else
        error "❌ 缺少必要的RBAC权限"
        check_failed=true
    fi
    
    # 检查磁盘空间
    info "检查本地磁盘空间..."
    local available_space=$(df . | awk 'NR==2 {print $4}')
    if [ "$available_space" -gt 1048576 ]; then  # 1GB in KB
        log "✅ 本地磁盘空间充足"
    else
        warn "本地磁盘空间不足1GB，证书生成可能受影响"
    fi
    
    # 检查现有安装
    info "检查现有Kafka安装..."
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        warn "命名空间 $NAMESPACE 已存在"
        if kubectl get pods -n "$NAMESPACE" &> /dev/null; then
            local pod_count=$(kubectl get pods -n "$NAMESPACE" --no-headers | wc -l)
            if [ "$pod_count" -gt 0 ]; then
                warn "发现现有Kafka安装，请考虑清理后重新部署"
                kubectl get pods -n "$NAMESPACE" | tee -a "$LOG_FILE"
            fi
        fi
    fi
    
    # 检查必要文件
    info "检查配置文件..."
    local required_files=(
        "$KAFKA_DIR/kafka-statefulset-ha-mtls.yaml"
        "$KAFKA_DIR/kafka-service-mtls.yaml"
        "$KAFKA_DIR/kafka-client-mtls-config.yaml"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            error "必需文件不存在: $file"
            check_failed=true
        else
            log "✅ 配置文件存在: $(basename $file)"
        fi
    done
    
    if [ "$check_failed" = true ]; then
        error "❌ 环境检查失败，请解决上述问题后重试"
        return 1
    else
        log "✅ 环境检查通过"
        return 0
    fi
}

# 生成证书
generate_certificates() {
    log "🔐 生成mTLS证书..."
    
    if kubectl get secret kafka-keystore -n $NAMESPACE &> /dev/null; then
        warn "证书已存在，跳过生成"
        return 0
    fi
    
    if [ -f "$SCRIPT_DIR/generate-certs.sh" ]; then
        if bash "$SCRIPT_DIR/generate-certs.sh" 2>&1 | tee -a "$LOG_FILE"; then
            log "✅ 证书生成完成"
        else
            error "❌ 证书生成失败"
            return 1
        fi
    else
        error "❌ 证书生成脚本不存在: $SCRIPT_DIR/generate-certs.sh"
        return 1
    fi
}

# 部署命名空间
deploy_namespace() {
    log "📝 创建命名空间..."
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    log "✅ 命名空间创建完成"
}

# 部署Kafka集群
deploy_kafka_cluster() {
    log "☕ 部署mTLS Kafka集群..."
    
    # 部署服务
    info "部署Kafka服务..."
    kubectl apply -f "$KAFKA_DIR/kafka-service-mtls.yaml"
    
    # 部署StatefulSet
    info "部署Kafka StatefulSet..."
    kubectl apply -f "$KAFKA_DIR/kafka-statefulset-ha-mtls.yaml"
    
    # 部署客户端配置
    info "部署客户端配置..."
    kubectl apply -f "$KAFKA_DIR/kafka-client-mtls-config.yaml"
    
    # 等待集群就绪
    log "⏳ 等待Kafka集群启动（最多10分钟）..."
    if kubectl wait --for=condition=ready pod -l app=kafka -n $NAMESPACE --timeout=600s; then
        log "✅ Kafka集群部署完成"
    else
        error "❌ Kafka集群启动超时"
        return 1
    fi
}

# 验证部署
verify_deployment() {
    log "🔍 验证部署..."
    
    if [ -f "$SCRIPT_DIR/verify-deployment.sh" ]; then
        if bash "$SCRIPT_DIR/verify-deployment.sh" 2>&1 | tee -a "$LOG_FILE"; then
            log "✅ 部署验证通过"
        else
            warn "⚠️ 部署验证有问题，请检查日志"
        fi
    else
        warn "验证脚本不存在，跳过验证"
    fi
}

# 显示集群状态
show_status() {
    log "📊 Kafka集群状态:"
    echo ""
    
    echo "命名空间状态:"
    kubectl get namespace "$NAMESPACE" 2>/dev/null || echo "命名空间 $NAMESPACE 不存在"
    echo ""
    
    echo "Pods状态:"
    kubectl get pods -n $NAMESPACE -l app=kafka 2>/dev/null || echo "未找到Kafka Pods"
    echo ""
    
    echo "服务状态:"
    kubectl get svc -n $NAMESPACE 2>/dev/null || echo "未找到服务"
    echo ""
    
    echo "PVC状态:"
    kubectl get pvc -n $NAMESPACE 2>/dev/null || echo "未找到PVC"
    echo ""
    
    echo "Secret状态:"
    kubectl get secrets -n $NAMESPACE 2>/dev/null || echo "未找到Secret"
    echo ""
    
    # 获取外部IP
    if kubectl get svc kafka-external-ssl -n $NAMESPACE &> /dev/null; then
        EXTERNAL_IP=$(kubectl get svc kafka-external-ssl -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "待分配")
        
        echo "连接信息:"
        echo "=========================================="
        echo "内部连接: kafka-0.kafka-headless.$NAMESPACE.svc.cluster.local:9092"
        echo "外部mTLS: $EXTERNAL_IP:9094,9095,9096"
        echo "证书位置: kubectl get secret kafka-keystore -n $NAMESPACE"
    fi
}

# 清理集群
cleanup_cluster() {
    warn "⚠️  即将清理Kafka集群，这将删除所有数据！"
    read -p "确认清理? (yes/no): " -r
    if [[ $REPLY != "yes" ]]; then
        info "取消清理操作"
        exit 0
    fi
    
    log "🗑️ 清理Kafka集群..."
    
    # 删除Kafka资源
    kubectl delete -f "$KAFKA_DIR/kafka-statefulset-ha-mtls.yaml" --ignore-not-found=true
    kubectl delete -f "$KAFKA_DIR/kafka-service-mtls.yaml" --ignore-not-found=true
    kubectl delete -f "$KAFKA_DIR/kafka-client-mtls-config.yaml" --ignore-not-found=true
    
    # 删除PVC
    kubectl delete pvc -l app=kafka -n $NAMESPACE --ignore-not-found=true
    
    # 删除证书
    kubectl delete secret kafka-keystore kafka-tls-certs -n $NAMESPACE --ignore-not-found=true
    
    log "✅ 集群清理完成"
}

# 交互式模式
interactive_mode() {
    log "🎯 进入交互式部署模式"
    
    echo ""
    echo "mTLS Kafka高可用集群部署向导"
    echo "============================="
    
    # 环境检查
    echo ""
    read -p "是否运行环境检查? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if ! check_environment; then
            error "环境检查失败，是否继续?"
            read -p "继续部署? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
    
    # 证书生成
    echo ""
    read -p "是否生成TLS证书? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        deploy_namespace
        if ! generate_certificates; then
            error "证书生成失败"
            exit 1
        fi
    fi
    
    # Kafka部署
    echo ""
    read -p "是否部署Kafka集群? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        deploy_namespace
        if ! deploy_kafka_cluster; then
            error "Kafka部署失败"
            exit 1
        fi
    fi
    
    # 验证
    echo ""
    read -p "是否验证部署? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if ! verify_deployment; then
            error "部署验证失败"
        fi
    fi
    
    log "🎉 交互式部署完成！"
    show_status
}

# 完整部署流程
full_deploy() {
    local skip_check=false
    local skip_certs=false
    local skip_verify=false
    
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-check)
                skip_check=true
                shift
                ;;
            --skip-certs)
                skip_certs=true
                shift
                ;;
            --skip-verify)
                skip_verify=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    log "🚀 开始mTLS Kafka集群完整部署"
    log "📝 日志文件: $LOG_FILE"
    
    # 1. 环境检查
    if [ "$skip_check" = false ]; then
        if ! check_environment; then
            error "环境检查失败，部署终止"
            exit 1
        fi
    else
        warn "跳过环境检查"
    fi
    
    # 2. 部署命名空间
    deploy_namespace
    
    # 3. 生成证书
    if [ "$skip_certs" = false ]; then
        if ! generate_certificates; then
            error "证书生成失败，部署终止"
            exit 1
        fi
    else
        warn "跳过证书生成"
    fi
    
    # 4. 部署Kafka
    if ! deploy_kafka_cluster; then
        error "Kafka部署失败，部署终止"
        exit 1
    fi
    
    # 5. 验证部署
    if [ "$skip_verify" = false ]; then
        if ! verify_deployment; then
            warn "部署验证失败，但集群可能仍然可用"
        fi
    else
        warn "跳过部署验证"
    fi
    
    log "🎉 mTLS Kafka集群部署完成！"
    log "📝 日志文件: $LOG_FILE"
    
    # 显示最终状态
    show_status
}

# 主函数
main() {
    # 解析全局参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --log-file)
                LOG_FILE="$2"
                shift 2
                ;;
            --interactive)
                interactive_mode
                exit 0
                ;;
            --help)
                show_help
                exit 0
                ;;
            -*)
                break
                ;;
            *)
                break
                ;;
        esac
    done
    
    # 创建日志目录
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # 解析命令
    local command="${1:-deploy}"
    shift || true
    
    case "$command" in
        deploy)
            full_deploy "$@"
            ;;
        check)
            check_environment
            ;;
        certs)
            deploy_namespace
            generate_certificates
            ;;
        kafka)
            deploy_namespace
            deploy_kafka_cluster
            ;;
        verify)
            verify_deployment
            ;;
        status)
            show_status
            ;;
        cleanup)
            cleanup_cluster
            ;;
        help)
            show_help
            ;;
        *)
            error "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

# 捕获中断信号
trap 'error "部署被中断"; exit 1' INT TERM

# 运行主函数
main "$@" 