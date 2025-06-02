#!/bin/bash

# Kafka证书验证脚本
# 包含所有证书验证方法的综合脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 默认证书路径
CA_CERT="./ca.crt"
CLIENT_CERT="./client.crt"
CLIENT_KEY="./client.key"
SERVER_CERT="./server.crt"
SERVER_KEY="./server.key"

# 检查工具是否存在
check_tools() {
    echo -e "${BLUE}=== 检查必需工具 ===${NC}"
    
    local tools=("openssl" "kubectl")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            echo -e "✅ $tool 已安装"
        else
            echo -e "❌ $tool 未安装"
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo -e "${RED}错误: 缺少必需工具: ${missing_tools[*]}${NC}"
        exit 1
    fi
    echo
}

# 显示使用方法
show_usage() {
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  -h, --help              显示此帮助信息"
    echo "  --ca-cert PATH          CA证书路径 (默认: $CA_CERT)"
    echo "  --client-cert PATH      客户端证书路径 (默认: $CLIENT_CERT)"
    echo "  --client-key PATH       客户端私钥路径 (默认: $CLIENT_KEY)"
    echo "  --server-cert PATH      服务器证书路径 (默认: $SERVER_CERT)"
    echo "  --server-key PATH       服务器私钥路径 (默认: $SERVER_KEY)"
    echo "  --skip-k8s              跳过Kubernetes证书检查"
    echo
    echo "示例:"
    echo "  $0                      使用默认路径验证所有证书"
    echo "  $0 --skip-k8s           只验证本地证书文件"
    echo "  $0 --ca-cert /path/to/ca.crt --client-cert /path/to/client.crt"
    echo
}

# 解析命令行参数
parse_args() {
    SKIP_K8S=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            --ca-cert)
                CA_CERT="$2"
                shift 2
                ;;
            --client-cert)
                CLIENT_CERT="$2"
                shift 2
                ;;
            --client-key)
                CLIENT_KEY="$2"
                shift 2
                ;;
            --server-cert)
                SERVER_CERT="$2"
                shift 2
                ;;
            --server-key)
                SERVER_KEY="$2"
                shift 2
                ;;
            --skip-k8s)
                SKIP_K8S=true
                shift
                ;;
            *)
                echo -e "${RED}未知选项: $1${NC}"
                show_usage
                exit 1
                ;;
        esac
    done
}

# 检查文件是否存在
check_files() {
    echo -e "${BLUE}=== 检查证书文件 ===${NC}"
    
    local files=("$CA_CERT" "$CLIENT_CERT" "$CLIENT_KEY")
    if [ -f "$SERVER_CERT" ] && [ -f "$SERVER_KEY" ]; then
        files+=("$SERVER_CERT" "$SERVER_KEY")
    fi
    
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            echo -e "✅ $file 存在"
        else
            echo -e "❌ $file 不存在"
            return 1
        fi
    done
    echo
}

# 验证证书基本信息
verify_cert_info() {
    local cert_file="$1"
    local cert_name="$2"
    
    echo -e "${CYAN}--- $cert_name 基本信息 ---${NC}"
    
    # 检查证书格式
    if openssl x509 -in "$cert_file" -noout -text >/dev/null 2>&1; then
        echo -e "✅ 证书格式有效"
    else
        echo -e "❌ 证书格式无效"
        return 1
    fi
    
    # 显示证书主题和签发者
    local subject=$(openssl x509 -in "$cert_file" -noout -subject | sed 's/^subject= *//')
    local issuer=$(openssl x509 -in "$cert_file" -noout -issuer | sed 's/^issuer= *//')
    local not_before=$(openssl x509 -in "$cert_file" -noout -startdate | sed 's/^notBefore=//')
    local not_after=$(openssl x509 -in "$cert_file" -noout -enddate | sed 's/^notAfter=//')
    
    echo -e "主题: $subject"
    echo -e "签发者: $issuer"
    echo -e "有效期: $not_before 到 $not_after"
    
    # 检查证书是否过期
    if openssl x509 -in "$cert_file" -noout -checkend 0 >/dev/null 2>&1; then
        echo -e "✅ 证书未过期"
    else
        echo -e "❌ 证书已过期"
    fi
    
    echo
}

# 验证证书链
verify_cert_chain() {
    echo -e "${PURPLE}=== 证书链验证 ===${NC}"
    
    echo -e "${CYAN}--- 验证客户端证书链 ---${NC}"
    if openssl verify -CAfile "$CA_CERT" "$CLIENT_CERT" 2>/dev/null; then
        echo -e "✅ 客户端证书链验证成功"
    else
        echo -e "❌ 客户端证书链验证失败"
        openssl verify -CAfile "$CA_CERT" "$CLIENT_CERT"
    fi
    
    if [ -f "$SERVER_CERT" ]; then
        echo -e "${CYAN}--- 验证服务器证书链 ---${NC}"
        if openssl verify -CAfile "$CA_CERT" "$SERVER_CERT" 2>/dev/null; then
            echo -e "✅ 服务器证书链验证成功"
        else
            echo -e "❌ 服务器证书链验证失败"
            openssl verify -CAfile "$CA_CERT" "$SERVER_CERT"
        fi
    fi
    
    echo
}

# 验证证书指纹
verify_fingerprints() {
    echo -e "${PURPLE}=== 证书指纹验证 ===${NC}"
    
    echo -e "${CYAN}--- CA证书指纹 ---${NC}"
    local ca_fingerprint=$(openssl x509 -in "$CA_CERT" -noout -fingerprint -sha256 | sed 's/^SHA256 Fingerprint=//')
    echo -e "CA证书 SHA256: $ca_fingerprint"
    
    echo -e "${CYAN}--- 客户端证书指纹 ---${NC}"
    local client_fingerprint=$(openssl x509 -in "$CLIENT_CERT" -noout -fingerprint -sha256 | sed 's/^SHA256 Fingerprint=//')
    echo -e "客户端证书 SHA256: $client_fingerprint"
    
    if [ -f "$SERVER_CERT" ]; then
        echo -e "${CYAN}--- 服务器证书指纹 ---${NC}"
        local server_fingerprint=$(openssl x509 -in "$SERVER_CERT" -noout -fingerprint -sha256 | sed 's/^SHA256 Fingerprint=//')
        echo -e "服务器证书 SHA256: $server_fingerprint"
    fi
    
    echo
}

# 验证签发者
verify_issuers() {
    echo -e "${PURPLE}=== 签发者验证 ===${NC}"
    
    local ca_subject=$(openssl x509 -in "$CA_CERT" -noout -subject | sed 's/^subject= *//')
    local client_issuer=$(openssl x509 -in "$CLIENT_CERT" -noout -issuer | sed 's/^issuer= *//')
    
    echo -e "${CYAN}--- 签发者比较 ---${NC}"
    echo -e "CA主题: $ca_subject"
    echo -e "客户端证书签发者: $client_issuer"
    
    if [ "$ca_subject" = "$client_issuer" ]; then
        echo -e "✅ 客户端证书由正确的CA签发"
    else
        echo -e "❌ 客户端证书签发者不匹配"
    fi
    
    if [ -f "$SERVER_CERT" ]; then
        local server_issuer=$(openssl x509 -in "$SERVER_CERT" -noout -issuer | sed 's/^issuer= *//')
        echo -e "服务器证书签发者: $server_issuer"
        
        if [ "$ca_subject" = "$server_issuer" ]; then
            echo -e "✅ 服务器证书由正确的CA签发"
        else
            echo -e "❌ 服务器证书签发者不匹配"
        fi
    fi
    
    echo
}

# 验证证书用途
verify_purposes() {
    echo -e "${PURPLE}=== 证书用途验证 ===${NC}"
    
    echo -e "${CYAN}--- 客户端证书用途 ---${NC}"
    if openssl x509 -in "$CLIENT_CERT" -noout -purpose | grep -q "SSL client : Yes"; then
        echo -e "✅ 客户端证书可用于SSL客户端"
    else
        echo -e "❌ 客户端证书不能用于SSL客户端"
    fi
    
    if [ -f "$SERVER_CERT" ]; then
        echo -e "${CYAN}--- 服务器证书用途 ---${NC}"
        if openssl x509 -in "$SERVER_CERT" -noout -purpose | grep -q "SSL server : Yes"; then
            echo -e "✅ 服务器证书可用于SSL服务器"
        else
            echo -e "❌ 服务器证书不能用于SSL服务器"
        fi
    fi
    
    echo
}

# 验证私钥匹配
verify_key_matching() {
    echo -e "${PURPLE}=== 私钥匹配验证 ===${NC}"
    
    echo -e "${CYAN}--- 客户端证书和私钥匹配 ---${NC}"
    local client_cert_modulus=$(openssl x509 -in "$CLIENT_CERT" -noout -modulus | openssl md5)
    local client_key_modulus=$(openssl rsa -in "$CLIENT_KEY" -noout -modulus 2>/dev/null | openssl md5)
    
    if [ "$client_cert_modulus" = "$client_key_modulus" ]; then
        echo -e "✅ 客户端证书和私钥匹配"
    else
        echo -e "❌ 客户端证书和私钥不匹配"
        echo -e "证书模数: $client_cert_modulus"
        echo -e "私钥模数: $client_key_modulus"
    fi
    
    if [ -f "$SERVER_CERT" ] && [ -f "$SERVER_KEY" ]; then
        echo -e "${CYAN}--- 服务器证书和私钥匹配 ---${NC}"
        local server_cert_modulus=$(openssl x509 -in "$SERVER_CERT" -noout -modulus | openssl md5)
        local server_key_modulus=$(openssl rsa -in "$SERVER_KEY" -noout -modulus 2>/dev/null | openssl md5)
        
        if [ "$server_cert_modulus" = "$server_key_modulus" ]; then
            echo -e "✅ 服务器证书和私钥匹配"
        else
            echo -e "❌ 服务器证书和私钥不匹配"
            echo -e "证书模数: $server_cert_modulus"
            echo -e "私钥模数: $server_key_modulus"
        fi
    fi
    
    echo
}

# 验证Kubernetes中的证书
verify_k8s_certificates() {
    if [ "$SKIP_K8S" = true ]; then
        echo -e "${YELLOW}跳过Kubernetes证书检查${NC}"
        echo
        return
    fi
    
    echo -e "${PURPLE}=== Kubernetes证书验证 ===${NC}"
    
    # 检查kubectl是否可用
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${YELLOW}警告: 无法连接到Kubernetes集群，跳过K8s证书检查${NC}"
        echo
        return
    fi
    
    # 检查kafka命名空间中的证书
    echo -e "${CYAN}--- Kafka命名空间证书 ---${NC}"
    if kubectl get secret kafka-certs -n kafka >/dev/null 2>&1; then
        echo -e "✅ kafka命名空间中存在kafka-certs secret"
        
        # 获取并验证证书
        local k8s_ca=$(kubectl get secret kafka-certs -n kafka -o jsonpath='{.data.ca\.crt}' | base64 -d)
        local k8s_client_cert=$(kubectl get secret kafka-certs -n kafka -o jsonpath='{.data.client\.crt}' | base64 -d)
        
        # 比较指纹
        local local_ca_fp=$(openssl x509 -in "$CA_CERT" -noout -fingerprint -sha256)
        local k8s_ca_fp=$(echo "$k8s_ca" | openssl x509 -noout -fingerprint -sha256)
        
        if [ "$local_ca_fp" = "$k8s_ca_fp" ]; then
            echo -e "✅ Kubernetes中的CA证书与本地CA证书匹配"
        else
            echo -e "❌ Kubernetes中的CA证书与本地CA证书不匹配"
        fi
        
        local local_client_fp=$(openssl x509 -in "$CLIENT_CERT" -noout -fingerprint -sha256)
        local k8s_client_fp=$(echo "$k8s_client_cert" | openssl x509 -noout -fingerprint -sha256)
        
        if [ "$local_client_fp" = "$k8s_client_fp" ]; then
            echo -e "✅ Kubernetes中的客户端证书与本地客户端证书匹配"
        else
            echo -e "❌ Kubernetes中的客户端证书与本地客户端证书不匹配"
        fi
    else
        echo -e "❌ kafka命名空间中不存在kafka-certs secret"
    fi
    
    # 检查opentelemetry命名空间中的证书
    echo -e "${CYAN}--- OpenTelemetry命名空间证书 ---${NC}"
    if kubectl get secret kafka-client-certs -n opentelemetry >/dev/null 2>&1; then
        echo -e "✅ opentelemetry命名空间中存在kafka-client-certs secret"
    else
        echo -e "❌ opentelemetry命名空间中不存在kafka-client-certs secret"
    fi
    
    echo
}

# 测试与Kafka的连接
test_kafka_connection() {
    echo -e "${PURPLE}=== Kafka连接测试 ===${NC}"
    
    echo -e "${CYAN}--- SSL连接测试 ---${NC}"
    
    # 使用不同端口测试连接
    local kafka_host="kafka.kafka.svc.cluster.local"
    local ports=(9092 9093 9094 9095)
    local port_descriptions=("INTERNAL_SSL" "EXTERNAL_SSL" "CONTROLLER" "KRAFT_API")
    
    for i in "${!ports[@]}"; do
        local port="${ports[$i]}"
        local desc="${port_descriptions[$i]}"
        
        echo -e "${CYAN}测试端口 $port ($desc)...${NC}"
        
        if timeout 5 openssl s_client -connect "$kafka_host:$port" \
            -cert "$CLIENT_CERT" -key "$CLIENT_KEY" -CAfile "$CA_CERT" \
            -verify_return_error -servername kafka.internal.cloud \
            </dev/null >/dev/null 2>&1; then
            echo -e "✅ 端口 $port 连接成功"
        else
            echo -e "❌ 端口 $port 连接失败"
        fi
    done
    
    echo
}

# 生成验证报告
generate_report() {
    echo -e "${GREEN}=== 验证报告 ===${NC}"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "验证时间: $timestamp"
    echo -e "CA证书: $CA_CERT"
    echo -e "客户端证书: $CLIENT_CERT"
    echo -e "客户端私钥: $CLIENT_KEY"
    
    if [ -f "$SERVER_CERT" ]; then
        echo -e "服务器证书: $SERVER_CERT"
    fi
    
    if [ -f "$SERVER_KEY" ]; then
        echo -e "服务器私钥: $SERVER_KEY"
    fi
    
    echo
    echo -e "${GREEN}验证完成！请查看以上结果确认证书配置正确。${NC}"
    echo
}

# 主函数
main() {
    echo -e "${GREEN}=== Kafka证书验证脚本 ===${NC}"
    echo -e "${GREEN}版本: 1.0${NC}"
    echo
    
    # 解析参数
    parse_args "$@"
    
    # 检查工具
    check_tools
    
    # 检查文件
    if ! check_files; then
        echo -e "${RED}错误: 部分证书文件不存在，请检查路径${NC}"
        exit 1
    fi
    
    # 验证证书基本信息
    verify_cert_info "$CA_CERT" "CA证书"
    verify_cert_info "$CLIENT_CERT" "客户端证书"
    
    if [ -f "$SERVER_CERT" ]; then
        verify_cert_info "$SERVER_CERT" "服务器证书"
    fi
    
    # 执行各种验证
    verify_cert_chain
    verify_fingerprints
    verify_issuers
    verify_purposes
    verify_key_matching
    verify_k8s_certificates
    # test_kafka_connection
    
    # 生成报告
    generate_report
}

# 如果脚本被直接执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 