#!/bin/bash

# TLS证书生成脚本 - 用于Kafka mTLS配置
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="${SCRIPT_DIR}/../../../certs"
NAMESPACE="confluent-kafka"

# 创建证书目录
mkdir -p "${CERT_DIR}"

echo "🔐 开始生成Kafka mTLS证书..."

# 配置证书参数
CERT_VALIDITY=365
KEY_SIZE=2048
KEYSTORE_PASSWORD="password"
TRUSTSTORE_PASSWORD="password"

# Kafka集群服务名称
KAFKA_HOSTS=(
    "kafka-0.kafka-headless.${NAMESPACE}.svc.cluster.local"
    "kafka-1.kafka-headless.${NAMESPACE}.svc.cluster.local"
    "kafka-2.kafka-headless.${NAMESPACE}.svc.cluster.local"
    "kafka.${NAMESPACE}.svc.cluster.local"
    "localhost"
)

cd "${CERT_DIR}"

# 1. 生成CA私钥
echo "📝 生成CA私钥..."
openssl genrsa -out ca.key ${KEY_SIZE}

# 2. 生成CA证书
echo "📝 生成CA证书..."
openssl req -new -x509 -key ca.key -sha256 -subj "/C=CN/ST=Beijing/L=Beijing/O=Kafka/OU=IT/CN=KafkaCA" -days ${CERT_VALIDITY} -out ca.crt

# 3. 生成Kafka服务器私钥
echo "📝 生成Kafka服务器私钥..."
openssl genrsa -out kafka.key ${KEY_SIZE}

# 4. 创建服务器证书配置文件
echo "📝 创建服务器证书配置..."
cat > kafka.conf <<EOF
[req]
default_bits = ${KEY_SIZE}
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=CN
ST=Beijing
L=Beijing
O=Kafka
OU=IT
CN=kafka.${NAMESPACE}.svc.cluster.local

[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = kafka-0.kafka-headless.${NAMESPACE}.svc.cluster.local
DNS.2 = kafka-1.kafka-headless.${NAMESPACE}.svc.cluster.local
DNS.3 = kafka-2.kafka-headless.${NAMESPACE}.svc.cluster.local
DNS.4 = kafka.${NAMESPACE}.svc.cluster.local
DNS.5 = kafka-headless.${NAMESPACE}.svc.cluster.local
DNS.6 = localhost
DNS.7 = *.kafka-headless.${NAMESPACE}.svc.cluster.local
IP.1 = 127.0.0.1
EOF

# 5. 生成服务器证书签名请求
echo "📝 生成Kafka服务器CSR..."
openssl req -new -key kafka.key -out kafka.csr -config kafka.conf

# 6. 使用CA签名服务器证书
echo "📝 使用CA签名Kafka服务器证书..."
openssl x509 -req -in kafka.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out kafka.crt -days ${CERT_VALIDITY} -extensions v3_req -extfile kafka.conf

# 7. 生成客户端私钥
echo "📝 生成客户端私钥..."
openssl genrsa -out client.key ${KEY_SIZE}

# 8. 生成客户端证书签名请求
echo "📝 生成客户端CSR..."
openssl req -new -key client.key -out client.csr -subj "/C=CN/ST=Beijing/L=Beijing/O=Kafka/OU=IT/CN=kafka-client"

# 9. 使用CA签名客户端证书
echo "📝 使用CA签名客户端证书..."
openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out client.crt -days ${CERT_VALIDITY}

# 10. 创建Java KeyStore和TrustStore
echo "📝 创建Java KeyStore..."

# 将服务器证书和私钥打包成PKCS12格式
openssl pkcs12 -export -in kafka.crt -inkey kafka.key -out kafka.p12 -name kafka -CAfile ca.crt -caname root -password pass:${KEYSTORE_PASSWORD}

# 转换为JKS格式
keytool -importkeystore -deststorepass ${KEYSTORE_PASSWORD} -destkeypass ${KEYSTORE_PASSWORD} -destkeystore kafka.server.keystore.jks -srckeystore kafka.p12 -srcstoretype PKCS12 -srcstorepass ${KEYSTORE_PASSWORD} -alias kafka

# 创建TrustStore并导入CA证书
keytool -keystore kafka.server.truststore.jks -alias CARoot -import -file ca.crt -storepass ${TRUSTSTORE_PASSWORD} -noprompt

# 创建客户端KeyStore
openssl pkcs12 -export -in client.crt -inkey client.key -out client.p12 -name client -CAfile ca.crt -caname root -password pass:${KEYSTORE_PASSWORD}
keytool -importkeystore -deststorepass ${KEYSTORE_PASSWORD} -destkeypass ${KEYSTORE_PASSWORD} -destkeystore client.keystore.jks -srckeystore client.p12 -srcstoretype PKCS12 -srcstorepass ${KEYSTORE_PASSWORD} -alias client

echo "📝 创建Kubernetes Secret..."

# 检查kubectl是否可用
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl未找到，请确保已安装kubectl"
    exit 1
fi

# 创建命名空间（如果不存在）
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# 删除旧的secret（如果存在）
kubectl delete secret kafka-tls-certs kafka-keystore -n ${NAMESPACE} --ignore-not-found

# 创建TLS证书Secret
kubectl create secret generic kafka-tls-certs -n ${NAMESPACE} \
    --from-file=ca.crt=ca.crt \
    --from-file=kafka.crt=kafka.crt \
    --from-file=kafka.key=kafka.key \
    --from-file=client.crt=client.crt \
    --from-file=client.key=client.key

# 创建KeyStore Secret
kubectl create secret generic kafka-keystore -n ${NAMESPACE} \
    --from-file=kafka.server.keystore.jks=kafka.server.keystore.jks \
    --from-file=kafka.server.truststore.jks=kafka.server.truststore.jks \
    --from-file=client.keystore.jks=client.keystore.jks \
    --from-literal=keystore-password=${KEYSTORE_PASSWORD} \
    --from-literal=truststore-password=${TRUSTSTORE_PASSWORD}

echo "✅ 证书生成完成！"
echo "📁 证书文件位置: ${CERT_DIR}"
echo "🔑 KeyStore密码: ${KEYSTORE_PASSWORD}"
echo "🔑 TrustStore密码: ${TRUSTSTORE_PASSWORD}"

# 验证证书
echo "🔍 验证证书..."
openssl x509 -in kafka.crt -text -noout | grep -A 1 "Subject Alternative Name"

# 清理临时文件
rm -f kafka.csr client.csr kafka.p12 client.p12 kafka.conf ca.srl

echo "🎉 mTLS证书配置完成！" 