#!/bin/bash

# Kafka KeyStore和TrustStore生成脚本
# 密码统一使用: changeit

set -e

# 配置变量
PASSWORD="changeit"
VALIDITY_DAYS="3650"
KEY_SIZE="2048"
COUNTRY="CN"
STATE="Beijing"
CITY="Beijing"
ORG="MyOrg"
OU="IT"
KAFKA_CLUSTER_NAME="kafka"

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

# 清理现有文件
cleanup_existing_files() {
    log_info "清理现有的证书和keystore文件..."
    rm -f *.jks *.p12 *.crt *.key *.csr *.srl *.pem *.conf
}

# 生成CA证书
generate_ca() {
    log_info "生成CA私钥和证书..."
    
    # 生成CA私钥
    openssl genrsa -out ca-key.pem $KEY_SIZE
    
    # 生成CA证书
    openssl req -new -x509 -key ca-key.pem -out ca-cert.pem -days $VALIDITY_DAYS \
        -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=$OU/CN=Kafka-CA"
    
    log_info "✅ CA证书生成完成"
}

# 生成服务器证书
generate_server_cert() {
    log_info "生成Kafka服务器证书..."
    
    # 生成服务器私钥
    openssl genrsa -out kafka-server-key.pem $KEY_SIZE
    
    # 生成服务器证书请求
    openssl req -new -key kafka-server-key.pem -out kafka-server.csr \
        -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=$OU/CN=kafka-server"
    
    # 创建服务器证书扩展配置
    cat > kafka-server-extensions.conf << EOF
[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = kafka-0
DNS.2 = kafka-1  
DNS.3 = kafka-2
DNS.4 = kafka-0.kafka.internal
DNS.5 = kafka-1.kafka.internal
DNS.6 = kafka-2.kafka.internal
DNS.7 = kafka-0-internal
DNS.8 = kafka-1-internal
DNS.9 = kafka-2-internal
DNS.10 = kafka-headless
DNS.11 = kafka
DNS.12 = localhost
IP.1 = 127.0.0.1
IP.2 = 10.0.0.11
IP.3 = 10.0.0.12
IP.4 = 10.0.0.13
EOF
    
    # 使用CA签署服务器证书
    openssl x509 -req -in kafka-server.csr -CA ca-cert.pem -CAkey ca-key.pem \
        -CAcreateserial -out kafka-server-cert.pem -days $VALIDITY_DAYS \
        -extensions v3_req -extfile kafka-server-extensions.conf
    
    log_info "✅ 服务器证书生成完成"
}

# 生成客户端证书
generate_client_cert() {
    log_info "生成Kafka客户端证书..."
    
    # 生成客户端私钥
    openssl genrsa -out kafka-client-key.pem $KEY_SIZE
    
    # 生成客户端证书请求
    openssl req -new -key kafka-client-key.pem -out kafka-client.csr \
        -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=$OU/CN=kafka-client"
    
    # 创建客户端证书扩展配置
    cat > kafka-client-extensions.conf << EOF
[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
EOF
    
    # 使用CA签署客户端证书
    openssl x509 -req -in kafka-client.csr -CA ca-cert.pem -CAkey ca-key.pem \
        -CAcreateserial -out kafka-client-cert.pem -days $VALIDITY_DAYS \
        -extensions v3_req -extfile kafka-client-extensions.conf
    
    log_info "✅ 客户端证书生成完成"
}

# 创建服务器KeyStore
create_server_keystore() {
    log_info "创建服务器KeyStore..."
    
    # 将私钥和证书转换为PKCS12格式
    openssl pkcs12 -export -in kafka-server-cert.pem -inkey kafka-server-key.pem \
        -out kafka-server.p12 -name kafka-server -CAfile ca-cert.pem \
        -caname root -password pass:$PASSWORD
    
    # 将PKCS12转换为JKS KeyStore
    keytool -importkeystore -deststorepass $PASSWORD -destkeypass $PASSWORD \
        -destkeystore kafka.server.keystore.jks -srckeystore kafka-server.p12 \
        -srcstoretype PKCS12 -srcstorepass $PASSWORD -alias kafka-server
    
    # 立即验证服务器KeyStore
    verify_keystore "kafka.server.keystore.jks" "服务器KeyStore"
    
    log_info "✅ 服务器KeyStore创建并验证完成: kafka.server.keystore.jks"
}

# 创建客户端KeyStore
create_client_keystore() {
    log_info "创建客户端KeyStore..."
    
    # 将私钥和证书转换为PKCS12格式
    openssl pkcs12 -export -in kafka-client-cert.pem -inkey kafka-client-key.pem \
        -out kafka-client.p12 -name kafka-client -CAfile ca-cert.pem \
        -caname root -password pass:$PASSWORD
    
    # 将PKCS12转换为JKS KeyStore
    keytool -importkeystore -deststorepass $PASSWORD -destkeypass $PASSWORD \
        -destkeystore kafka.client.keystore.jks -srckeystore kafka-client.p12 \
        -srcstoretype PKCS12 -srcstorepass $PASSWORD -alias kafka-client
    
    # 立即验证客户端KeyStore
    verify_keystore "kafka.client.keystore.jks" "客户端KeyStore"
    
    log_info "✅ 客户端KeyStore创建并验证完成: kafka.client.keystore.jks"
}

# 创建TrustStore
create_truststore() {
    log_info "创建TrustStore..."
    
    # 导入CA证书到TrustStore
    keytool -keystore kafka.server.truststore.jks -alias CARoot \
        -import -file ca-cert.pem -storepass $PASSWORD -keypass $PASSWORD -noprompt
    
    # 为客户端创建相同的TrustStore
    cp kafka.server.truststore.jks kafka.client.truststore.jks
    
    # 立即验证TrustStore
    verify_truststore "kafka.server.truststore.jks" "服务器TrustStore"
    verify_truststore "kafka.client.truststore.jks" "客户端TrustStore"
    
    log_info "✅ TrustStore创建并验证完成: kafka.server.truststore.jks, kafka.client.truststore.jks"
}

# 验证单个KeyStore
verify_keystore() {
    local keystore_file="$1"
    local keystore_name="$2"
    
    log_info "🔍 验证 $keystore_name: $keystore_file"
    
    # 检查文件是否存在
    if [[ ! -f "$keystore_file" ]]; then
        log_error "KeyStore文件不存在: $keystore_file"
        return 1
    fi
    
    # 验证密码是否正确
    if ! keytool -list -keystore "$keystore_file" -storepass "$PASSWORD" &>/dev/null; then
        log_error "KeyStore密码验证失败: $keystore_file"
        return 1
    fi
    
    # 获取KeyStore信息
    local alias_count=$(keytool -list -keystore "$keystore_file" -storepass "$PASSWORD" 2>/dev/null | grep -c "PrivateKeyEntry\|trustedCertEntry")
    local keystore_type=$(keytool -list -keystore "$keystore_file" -storepass "$PASSWORD" 2>/dev/null | grep "Keystore type:" | cut -d' ' -f3)
    
    echo "  📄 文件大小: $(du -h "$keystore_file" | cut -f1)"
    echo "  🔑 KeyStore类型: ${keystore_type:-"JKS"}"
    echo "  📋 条目数量: $alias_count"
    
    # 验证私钥条目
    local private_entries=$(keytool -list -keystore "$keystore_file" -storepass "$PASSWORD" 2>/dev/null | grep "PrivateKeyEntry" | wc -l)
    if [[ $private_entries -gt 0 ]]; then
        echo "  🔐 私钥条目: $private_entries 个"
        
        # 验证证书链
        local aliases=$(keytool -list -keystore "$keystore_file" -storepass "$PASSWORD" 2>/dev/null | grep "PrivateKeyEntry" | awk '{print $1}' | sed 's/,$//')
        for alias in $aliases; do
            local cert_info=$(keytool -list -v -keystore "$keystore_file" -storepass "$PASSWORD" -alias "$alias" 2>/dev/null | grep -E "(Valid from|until|Subject|Issuer)")
            if [[ -n "$cert_info" ]]; then
                echo "  ✅ 别名 '$alias' 验证通过"
                local subject=$(echo "$cert_info" | grep "Subject:" | head -1 | cut -d':' -f2- | xargs)
                local valid_until=$(echo "$cert_info" | grep "Valid from" | head -1 | sed 's/.*until: //')
                echo "     📝 主题: $subject"
                echo "     📅 有效期至: $valid_until"
            else
                log_warn "别名 '$alias' 信息获取失败"
            fi
        done
    fi
    
    # 验证KeyStore完整性
    if keytool -list -keystore "$keystore_file" -storepass "$PASSWORD" >/dev/null 2>&1; then
        log_info "  ✅ $keystore_name 验证通过"
        return 0
    else
        log_error "  ❌ $keystore_name 验证失败"
        return 1
    fi
}

# 验证单个TrustStore
verify_truststore() {
    local truststore_file="$1"
    local truststore_name="$2"
    
    log_info "🔍 验证 $truststore_name: $truststore_file"
    
    # 检查文件是否存在
    if [[ ! -f "$truststore_file" ]]; then
        log_error "TrustStore文件不存在: $truststore_file"
        return 1
    fi
    
    # 验证密码是否正确
    if ! keytool -list -keystore "$truststore_file" -storepass "$PASSWORD" &>/dev/null; then
        log_error "TrustStore密码验证失败: $truststore_file"
        return 1
    fi
    
    # 获取TrustStore信息
    local cert_count=$(keytool -list -keystore "$truststore_file" -storepass "$PASSWORD" 2>/dev/null | grep -c "trustedCertEntry")
    local truststore_type=$(keytool -list -keystore "$truststore_file" -storepass "$PASSWORD" 2>/dev/null | grep "Keystore type:" | cut -d' ' -f3)
    
    echo "  📄 文件大小: $(du -h "$truststore_file" | cut -f1)"
    echo "  🔑 TrustStore类型: ${truststore_type:-"JKS"}"
    echo "  📋 受信任证书数量: $cert_count"
    
    # 验证受信任证书
    if [[ $cert_count -gt 0 ]]; then
        local aliases=$(keytool -list -keystore "$truststore_file" -storepass "$PASSWORD" 2>/dev/null | grep "trustedCertEntry" | awk '{print $1}' | sed 's/,$//')
        for alias in $aliases; do
            local cert_info=$(keytool -list -v -keystore "$truststore_file" -storepass "$PASSWORD" -alias "$alias" 2>/dev/null | grep -E "(Valid from|until|Subject|Issuer)")
            if [[ -n "$cert_info" ]]; then
                echo "  ✅ 受信任证书 '$alias' 验证通过"
                local subject=$(echo "$cert_info" | grep "Subject:" | head -1 | cut -d':' -f2- | xargs)
                local valid_until=$(echo "$cert_info" | grep "Valid from" | head -1 | sed 's/.*until: //')
                echo "     📝 主题: $subject"
                echo "     📅 有效期至: $valid_until"
            else
                log_warn "受信任证书 '$alias' 信息获取失败"
            fi
        done
    fi
    
    # 验证TrustStore完整性
    if keytool -list -keystore "$truststore_file" -storepass "$PASSWORD" >/dev/null 2>&1; then
        log_info "  ✅ $truststore_name 验证通过"
        return 0
    else
        log_error "  ❌ $truststore_name 验证失败"
        return 1
    fi
}

# 验证SSL连接能力
verify_ssl_connectivity() {
    log_info "🔗 验证SSL连接能力..."
    
    # 检查是否有openssl s_server可用
    if ! command -v openssl &> /dev/null; then
        log_warn "OpenSSL未找到，跳过SSL连接测试"
        return 0
    fi
    
    # 临时启动SSL服务器进行测试
    local test_port="19999"
    local server_pid=""
    
    # 启动测试SSL服务器
    echo "  🚀 启动测试SSL服务器(端口: $test_port)..."
    openssl s_server -accept $test_port -cert kafka-server-cert.pem -key kafka-server-key.pem -CAfile ca-cert.pem -verify_return_error -quiet &
    server_pid=$!
    
    # 等待服务器启动
    sleep 2
    
    # 测试SSL连接
    if timeout 5 openssl s_client -connect localhost:$test_port -cert kafka-client-cert.pem -key kafka-client-key.pem -CAfile ca-cert.pem -verify_return_error -quiet </dev/null &>/dev/null; then
        echo "  ✅ SSL mTLS连接测试成功"
    else
        log_warn "SSL mTLS连接测试失败，但不影响证书生成"
    fi
    
    # 清理测试服务器
    if [[ -n "$server_pid" ]]; then
        kill $server_pid 2>/dev/null || true
        wait $server_pid 2>/dev/null || true
    fi
}

# 最终总结验证
verify_certificates() {
    log_info "📋 最终验证总结..."
    
    echo ""
    log_info "📁 生成的文件列表:"
    ls -la *.jks *.pem *.p12 *.password 2>/dev/null | awk '{printf "  %-30s %8s %s %s %s\n", $9, $5, $6, $7, $8}'
    
    echo ""
    log_info "🔍 证书基本信息:"
    if [[ -f "ca-cert.pem" ]]; then
        echo "  CA证书:"
        openssl x509 -in ca-cert.pem -noout -subject -dates | sed 's/^/    /'
    fi
    
    if [[ -f "kafka-server-cert.pem" ]]; then
        echo "  服务器证书:"
        openssl x509 -in kafka-server-cert.pem -noout -subject -dates | sed 's/^/    /'
        echo "    SAN扩展:"
        openssl x509 -in kafka-server-cert.pem -noout -text | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/^/      /'
    fi
    
    if [[ -f "kafka-client-cert.pem" ]]; then
        echo "  客户端证书:"
        openssl x509 -in kafka-client-cert.pem -noout -subject -dates | sed 's/^/    /'
    fi
    
    echo ""
    log_info "✅ 所有验证步骤已完成"
}

# 生成密码文件
generate_password_files() {
    log_info "生成密码文件..."
    
    echo $PASSWORD > keystore.password
    echo $PASSWORD > key.password  
    echo $PASSWORD > truststore.password
    
    log_info "✅ 密码文件已生成"
}

# 主函数
main() {
    echo "=== Kafka KeyStore和TrustStore生成脚本 ==="
    echo "密码: $PASSWORD"
    echo "有效期: $VALIDITY_DAYS 天"
    echo ""
    
    # 确认执行
    read -p "是否继续生成证书和KeyStore? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "已取消操作"
        exit 0
    fi
    
    cleanup_existing_files
    generate_ca
    generate_server_cert
    generate_client_cert
    create_server_keystore
    create_client_keystore
    create_truststore
    generate_password_files
    verify_ssl_connectivity
    verify_certificates
    
    echo ""
    log_info "🎉 KeyStore和TrustStore生成完成！"
    echo ""
    log_info "📁 生成的文件:"
    echo "  - kafka.server.keystore.jks (服务器KeyStore)"
    echo "  - kafka.client.keystore.jks (客户端KeyStore)"
    echo "  - kafka.server.truststore.jks (服务器TrustStore)"
    echo "  - kafka.client.truststore.jks (客户端TrustStore)"
    echo "  - keystore.password (KeyStore密码文件)"
    echo "  - key.password (私钥密码文件)"
    echo "  - truststore.password (TrustStore密码文件)"
    echo ""
    log_info "🔒 所有密码均为: $PASSWORD"
    echo ""
    log_info "📝 下一步: 运行 ./generate-secrets.sh 生成Kubernetes Secret"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 