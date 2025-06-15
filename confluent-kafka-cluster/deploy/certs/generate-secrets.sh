#!/bin/bash

# Kafka SSL Secrets 生成脚本
# 将KeyStore和TrustStore生成Kubernetes Secret部署清单

set -e

# 配置变量
SECRET_NAME="kafka-ssl-certs"
NAMESPACE="confluent-kafka"
OUTPUT_FILE="kafka-ssl-secrets.yaml"

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查必要文件
check_required_files() {
    log_info "检查必要的证书和KeyStore文件..."
    
    local required_files=(
        "kafka.server.keystore.jks"
        "kafka.client.keystore.jks"
        "kafka.server.truststore.jks"
        "kafka.client.truststore.jks"
        "keystore.password"
        "key.password"
        "truststore.password"
    )
    
    local missing_files=()
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        log_error "缺少以下必要文件:"
        printf '  - %s\n' "${missing_files[@]}"
        echo ""
        log_error "请先运行 ./generate-keystore-truststore.sh 生成这些文件"
        exit 1
    fi
    
    log_info "✅ 所有必要文件已存在"
}

# 编码文件为base64
encode_file() {
    local file_path="$1"
    if [[ -f "$file_path" ]]; then
        base64 -i "$file_path" | tr -d '\n'
    else
        log_error "文件不存在: $file_path"
        exit 1
    fi
}

# 编码密码文件为base64
encode_password() {
    local password_file="$1"
    if [[ -f "$password_file" ]]; then
        cat "$password_file" | base64 | tr -d '\n'
    else
        log_error "密码文件不存在: $password_file"
        exit 1
    fi
}

# 生成Secret YAML
generate_secret_yaml() {
    log_info "生成Kubernetes Secret YAML文件..."
    
    # 编码所有文件
    local SERVER_KEYSTORE=$(encode_file "kafka.server.keystore.jks")
    local CLIENT_KEYSTORE=$(encode_file "kafka.client.keystore.jks")
    local SERVER_TRUSTSTORE=$(encode_file "kafka.server.truststore.jks")
    local CLIENT_TRUSTSTORE=$(encode_file "kafka.client.truststore.jks")
    
    local KEYSTORE_PASSWORD=$(encode_password "keystore.password")
    local KEY_PASSWORD=$(encode_password "key.password")
    local TRUSTSTORE_PASSWORD=$(encode_password "truststore.password")
    
    # 生成YAML文件
    cat > "$OUTPUT_FILE" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: $SECRET_NAME
  namespace: $NAMESPACE
  labels:
    app: kafka
    component: ssl-certs
    created-by: generate-secrets-script
type: Opaque
data:
  # KeyStore文件
  kafka.server.keystore.jks: $SERVER_KEYSTORE
  kafka.client.keystore.jks: $CLIENT_KEYSTORE
  
  # TrustStore文件
  kafka.server.truststore.jks: $SERVER_TRUSTSTORE
  kafka.client.truststore.jks: $CLIENT_TRUSTSTORE
  
  # 密码文件
  keystore.password: $KEYSTORE_PASSWORD
  key.password: $KEY_PASSWORD
  truststore.password: $TRUSTSTORE_PASSWORD
  
  # 兼容性别名 (支持不同的命名约定)
  server.keystore.jks: $SERVER_KEYSTORE
  client.keystore.jks: $CLIENT_KEYSTORE
  server.truststore.jks: $SERVER_TRUSTSTORE
  client.truststore.jks: $CLIENT_TRUSTSTORE
  truststore.jks: $SERVER_TRUSTSTORE
  
  # 密码别名
  server.keystore.password: $KEYSTORE_PASSWORD
  server.key.password: $KEY_PASSWORD
  server.truststore.password: $TRUSTSTORE_PASSWORD
  client.keystore.password: $KEYSTORE_PASSWORD
  client.key.password: $KEY_PASSWORD
  client.truststore.password: $TRUSTSTORE_PASSWORD

---
# ConfigMap for SSL configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: kafka-ssl-config
  namespace: $NAMESPACE
  labels:
    app: kafka
    component: ssl-config
    created-by: generate-secrets-script
data:
  # SSL配置参数
  ssl.keystore.type: "JKS"
  ssl.truststore.type: "JKS"
  ssl.keystore.location: "/etc/kafka/secrets/kafka.server.keystore.jks"
  ssl.truststore.location: "/etc/kafka/secrets/kafka.server.truststore.jks"
  ssl.key.password: "changeit"
  ssl.keystore.password: "changeit"
  ssl.truststore.password: "changeit"
  
  # SSL协议配置
  ssl.protocol: "TLSv1.2"
  ssl.enabled.protocols: "TLSv1.2,TLSv1.3"
  ssl.cipher.suites: "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
  
  # 客户端认证配置
  ssl.client.auth: "required"
  ssl.endpoint.identification.algorithm: ""
EOF
    
    log_info "✅ Secret YAML文件已生成: $OUTPUT_FILE"
}

# 验证生成的YAML
validate_yaml() {
    log_info "验证生成的YAML文件..."
    
    if command -v kubectl &> /dev/null; then
        if kubectl --dry-run=client apply -f "$OUTPUT_FILE" &> /dev/null; then
            log_info "✅ YAML文件格式验证通过"
        else
            log_warn "⚠️  YAML文件格式可能有问题，请手动检查"
        fi
    else
        log_warn "⚠️  kubectl未安装，跳过YAML验证"
    fi
}

# 显示文件信息
show_file_info() {
    log_info "生成的文件信息:"
    
    echo ""
    echo "📁 Secret文件: $OUTPUT_FILE"
    echo "📊 文件大小: $(du -h "$OUTPUT_FILE" | cut -f1)"
    echo "📄 行数: $(wc -l < "$OUTPUT_FILE")"
    
    echo ""
    log_info "📋 Secret包含的数据:"
    kubectl --dry-run=client -o yaml apply -f "$OUTPUT_FILE" 2>/dev/null | \
        grep -E "^  [a-zA-Z].*:" | sed 's/^/  /' || {
        echo "  - kafka.server.keystore.jks"
        echo "  - kafka.client.keystore.jks"
        echo "  - kafka.server.truststore.jks"
        echo "  - kafka.client.truststore.jks"
        echo "  - keystore.password"
        echo "  - key.password" 
        echo "  - truststore.password"
        echo "  - [其他兼容性别名...]"
    }
}

# 显示部署说明
show_deployment_instructions() {
    echo ""
    log_info "📝 部署说明:"
    echo ""
    echo "1. 创建命名空间 (如果还未存在):"
    echo "   kubectl create namespace $NAMESPACE"
    echo ""
    echo "2. 部署Secret到Kubernetes:"
    echo "   kubectl apply -f $OUTPUT_FILE"
    echo ""
    echo "3. 验证Secret部署:"
    echo "   kubectl get secret $SECRET_NAME -n $NAMESPACE"
    echo "   kubectl describe secret $SECRET_NAME -n $NAMESPACE"
    echo ""
    echo "4. 查看Secret中的所有keys:"
    echo "   kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data}' | jq -r 'keys[]' | sort"
    echo ""
    echo "5. 在Pod中使用Secret:"
    echo "   volumes:"
    echo "   - name: kafka-ssl-certs"
    echo "     secret:"
    echo "       secretName: $SECRET_NAME"
    echo "   volumeMounts:"
    echo "   - name: kafka-ssl-certs"
    echo "     mountPath: /etc/kafka/secrets"
    echo "     readOnly: true"
    echo ""
    echo "6. 清理资源 (如需要):"
    echo "   kubectl delete secret $SECRET_NAME -n $NAMESPACE"
    echo "   kubectl delete configmap kafka-ssl-config -n $NAMESPACE"
}

# 主函数
main() {
    echo "=== Kafka SSL Secrets 生成脚本 ==="
    echo "Secret名称: $SECRET_NAME"
    echo "命名空间: $NAMESPACE"
    echo "输出文件: $OUTPUT_FILE"
    echo ""
    
    check_required_files
    generate_secret_yaml
    validate_yaml
    show_file_info
    show_deployment_instructions
    
    echo ""
    log_info "🎉 Secret部署清单生成完成！"
    echo ""
    log_info "📁 生成的文件:"
    echo "  - $OUTPUT_FILE (Kubernetes Secret + ConfigMap)"
    echo ""
    log_info "🚀 下一步: kubectl apply -f $OUTPUT_FILE"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --secret-name)
            SECRET_NAME="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2" 
            shift 2
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --secret-name NAME    Secret名称 (默认: kafka-ssl-certs)"
            echo "  --namespace NAMESPACE 命名空间 (默认: confluent-kafka)"
            echo "  --output FILE         输出文件 (默认: kafka-ssl-secrets.yaml)"
            echo "  -h, --help           显示帮助信息"
            exit 0
            ;;
        *)
            log_error "未知选项: $1"
            exit 1
            ;;
    esac
done

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 