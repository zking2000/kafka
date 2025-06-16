#!/bin/bash

# Loki 3.1.1 配置验证脚本
# 用于验证配置是否与Loki 3.1.1兼容

set -e

echo "🔍 正在验证 Loki 3.1.1 配置兼容性..."

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

# 创建临时测试配置
print_message $BLUE "创建临时配置文件进行验证..."
kubectl create configmap loki-config-test --from-file=loki-configmap.yaml --dry-run=client -o yaml > /tmp/loki-test-config.yaml

# 使用Docker验证配置
print_message $BLUE "使用Loki 3.1.1镜像验证配置..."
if docker run --rm -v "${PWD}/loki-configmap.yaml:/config/loki-configmap.yaml" grafana/loki:3.1.1 -config.file=/config/loki-configmap.yaml -verify-config=true 2>&1; then
    print_message $GREEN "✅ 配置验证通过！"
else
    print_message $RED "❌ 配置验证失败"
    print_message $YELLOW "请检查以下常见的Loki 3.1.1兼容性问题："
    echo ""
    echo "1. Schema配置需要使用 tsdb + v13 以支持结构化元数据"
    echo "2. 移除了 max_transfer_retries 配置"
    echo "3. table_manager 相关配置已废弃"
    echo "4. boltdb_shipper 改为 tsdb_shipper"
    echo "5. 某些默认值已改变（如 max_label_names_per_series: 15）"
    echo ""
    exit 1
fi

# 检查特定的兼容性问题
print_message $BLUE "检查特定的Loki 3.1.1兼容性问题..."

# 检查schema配置
if grep -q "schema: v13" loki-configmap.yaml && grep -q "store: tsdb" loki-configmap.yaml; then
    print_message $GREEN "✅ Schema配置兼容（使用tsdb + v13）"
else
    print_message $YELLOW "⚠️  建议使用 tsdb store 和 v13 schema 以完全支持Loki 3.1.1功能"
fi

# 检查是否移除了废弃配置
if ! grep -q "max_transfer_retries" loki-configmap.yaml; then
    print_message $GREEN "✅ 已移除废弃的 max_transfer_retries 配置"
else
    print_message $YELLOW "⚠️  发现废弃配置 max_transfer_retries，建议移除"
fi

if ! grep -q "table_manager" loki-configmap.yaml; then
    print_message $GREEN "✅ 已移除废弃的 table_manager 配置"
else
    print_message $YELLOW "⚠️  发现废弃配置 table_manager，建议移除"
fi

# 检查结构化元数据配置
if grep -q "allow_structured_metadata: true" loki-configmap.yaml; then
    print_message $GREEN "✅ 已启用结构化元数据支持"
else
    print_message $YELLOW "⚠️  建议启用结构化元数据支持：allow_structured_metadata: true"
fi

# 检查服务名配置
if grep -q "discover_service_name" loki-configmap.yaml; then
    print_message $GREEN "✅ 已配置服务名发现设置"
else
    print_message $YELLOW "⚠️  建议配置服务名发现设置以避免自动标签分配"
fi

print_message $GREEN "🎉 Loki 3.1.1 兼容性检查完成！"

echo ""
print_message $BLUE "📋 Loki 3.1.1 主要变化总结："
echo "• 结构化元数据默认启用（需要 tsdb + v13 schema）"
echo "• 自动服务名标签分配（可通过 discover_service_name: [] 禁用）"
echo "• max_label_names_per_series 默认值从30改为15"
echo "• distributor.max_line_size 默认256KB"
echo "• WAL 默认启用"
echo "• 移除了多个废弃配置项"
echo "• 新增多个性能和稳定性改进"

print_message $BLUE "🚀 如果验证通过，您可以安全地部署 Loki 3.1.1！" 