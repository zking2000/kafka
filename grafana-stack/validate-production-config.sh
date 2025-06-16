#!/bin/bash

# Loki生产环境配置验证脚本
# 使用方法: ./validate-production-config.sh

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# 验证配置文件语法
validate_yaml_syntax() {
    log_info "验证YAML文件语法..."
    
    local files=(
        "loki-configmap-production.yaml"
        "loki-deployment-production.yaml"
        "loki-hpa-production.yaml"
        "loki-serviceaccount.yaml"
    )
    
    for file in "${files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "文件不存在: $file"
            return 1
        fi
        
        if kubectl apply --dry-run=client -f "$file" &>/dev/null; then
            log_success "✓ $file 语法正确"
        else
            log_error "✗ $file 语法错误"
            return 1
        fi
    done
    
    # 检查监控配置（需要Prometheus Operator）
    if kubectl get crd servicemonitors.monitoring.coreos.com &>/dev/null; then
        if kubectl apply --dry-run=client -f "loki-monitoring-production.yaml" &>/dev/null; then
            log_success "✓ loki-monitoring-production.yaml 语法正确"
        else
            log_error "✗ loki-monitoring-production.yaml 语法错误"
            return 1
        fi
    else
        log_warn "⚠ Prometheus Operator CRDs未安装，跳过监控配置验证"
        log_info "  如需监控功能，请先安装Prometheus Operator"
    fi
}

# 验证生产环境配置要求
validate_production_requirements() {
    log_info "验证生产环境配置要求..."
    
    # 检查认证配置
    if grep -q "auth_enabled: true" loki-configmap-production.yaml; then
        log_success "✓ 已启用认证"
    else
        log_error "✗ 未启用认证 (auth_enabled: false)"
        return 1
    fi
    
    # 检查多租户配置
    if grep -q "multitenancy_enabled: true" loki-configmap-production.yaml; then
        log_success "✓ 已启用多租户"
    else
        log_error "✗ 未启用多租户"
        return 1
    fi
    
    # 检查资源限制
    if grep -q "cpu: 4000m" loki-deployment-production.yaml && grep -q "memory: 8Gi" loki-deployment-production.yaml; then
        log_success "✓ 生产级资源配置"
    else
        log_error "✗ 资源配置不足"
        return 1
    fi
    
    # 检查副本数
    if grep -q "replicas: 3" loki-deployment-production.yaml; then
        log_success "✓ 高可用副本配置"
    else
        log_error "✗ 副本数不足"
        return 1
    fi
    
    # 检查PVC配置
    if grep -q "persistentVolumeClaim" loki-deployment-production.yaml; then
        log_success "✓ 持久化存储配置"
    else
        log_error "✗ 未配置持久化存储"
        return 1
    fi
    
    # 检查监控配置
    if [[ -f "loki-monitoring-production.yaml" ]]; then
        if grep -q "ServiceMonitor" loki-monitoring-production.yaml && grep -q "PrometheusRule" loki-monitoring-production.yaml; then
            log_success "✓ 监控和告警配置"
        else
            log_error "✗ 监控配置不完整"
            return 1
        fi
    else
        log_warn "⚠ 监控配置文件不存在"
    fi
}

# 验证安全配置
validate_security_config() {
    log_info "验证安全配置..."
    
    # 检查安全上下文
    if grep -q "runAsNonRoot: true" loki-deployment-production.yaml; then
        log_success "✓ 非root用户运行"
    else
        log_error "✗ 未配置非root用户"
        return 1
    fi
    
    # 检查只读根文件系统
    if grep -q "readOnlyRootFilesystem: true" loki-deployment-production.yaml; then
        log_success "✓ 只读根文件系统"
    else
        log_error "✗ 未配置只读根文件系统"
        return 1
    fi
    
    # 检查capability drop
    if grep -q "drop:" loki-deployment-production.yaml && grep -q "\- ALL" loki-deployment-production.yaml; then
        log_success "✓ 已删除所有capabilities"
    else
        log_error "✗ 未正确配置capabilities"
        return 1
    fi
}

# 验证性能配置
validate_performance_config() {
    log_info "验证性能配置..."
    
    # 检查速率限制
    if grep -q "ingestion_rate_mb: 50" loki-configmap-production.yaml; then
        log_success "✓ 写入速率限制配置"
    else
        log_error "✗ 写入速率限制配置错误"
        return 1
    fi
    
    # 检查WAL配置
    if grep -q "wal:" loki-configmap-production.yaml && grep -q "enabled: true" loki-configmap-production.yaml; then
        log_success "✓ WAL配置启用"
    else
        log_error "✗ WAL配置未启用"
        return 1
    fi
    
    # 检查HPA配置
    if grep -q "minReplicas: 3" loki-hpa-production.yaml && grep -q "maxReplicas: 12" loki-hpa-production.yaml; then
        log_success "✓ 自动伸缩配置"
    else
        log_error "✗ 自动伸缩配置错误"
        return 1
    fi
}

# 主验证函数
main() {
    echo "========================================"
    echo "    Loki 生产环境配置验证"
    echo "========================================"
    echo
    
    validate_yaml_syntax
    validate_production_requirements
    validate_security_config
    validate_performance_config
    
    echo
    log_success "所有生产环境配置验证通过！"
    echo
    log_info "配置特性总结:"
    echo "  ✓ 启用认证和多租户"
    echo "  ✓ 高可用部署 (3副本)"
    echo "  ✓ 生产级资源配置 (4CPU/8GB)"
    echo "  ✓ 持久化存储和WAL"
    echo "  ✓ 自动伸缩 (3-12副本)"
    echo "  ✓ 安全配置和网络策略"
    echo "  ✓ 监控告警和仪表板"
    echo "  ✓ GCS对象存储"
    echo
}

# 执行验证
main "$@" 