#!/bin/bash

# Kafka mTLS - JKS 证书生成和更新脚本
# 为 Kafka 集群生成完整的 JKS 文件并更新 Kubernetes Secrets

# set -e

# 配置变量
KEYSTORE_PASSWORD="password123"
TRUSTSTORE_PASSWORD="password123"
KEY_PASSWORD="password123"
ALIAS_SERVER="kafka-server"
ALIAS_CLIENT="kafka-client"

echo "🔧 开始生成 JKS 文件..."

# 确保我们在正确的目录
if [[ ! -f "ca-cert.pem" ]]; then
    echo "❌ 错误: 请在包含 PEM 证书文件的目录中运行此脚本"
    exit 1
fi

# 1. 生成服务器 Keystore (包含服务器证书和私钥)
echo "1️⃣ 生成服务器 Keystore..."

# 首先将服务器证书和私钥转换为 PKCS12 格式
openssl pkcs12 -export -in server-cert.pem -inkey server-key.pem \
    -out server.p12 -name $ALIAS_SERVER \
    -password pass:$KEYSTORE_PASSWORD

# 然后转换为 JKS 格式
keytool -importkeystore -deststorepass $KEYSTORE_PASSWORD \
    -destkeypass $KEY_PASSWORD \
    -destkeystore kafka.server.keystore.jks \
    -srckeystore server.p12 -srcstoretype PKCS12 \
    -srcstorepass $KEYSTORE_PASSWORD \
    -alias $ALIAS_SERVER

# 2. 生成服务器 Truststore (包含 CA 证书)
echo "2️⃣ 生成服务器 Truststore..."
keytool -keystore kafka.server.truststore.jks \
    -alias CARoot -import -file ca-cert.pem \
    -storepass $TRUSTSTORE_PASSWORD -noprompt

# 3. 生成客户端 Keystore (包含客户端证书和私钥)
echo "3️⃣ 生成客户端 Keystore..."

# 将客户端证书和私钥转换为 PKCS12 格式
openssl pkcs12 -export -in client-cert.pem -inkey client-key.pem \
    -out client.p12 -name $ALIAS_CLIENT \
    -password pass:$KEYSTORE_PASSWORD

# 转换为 JKS 格式
keytool -importkeystore -deststorepass $KEYSTORE_PASSWORD \
    -destkeypass $KEY_PASSWORD \
    -destkeystore kafka.client.keystore.jks \
    -srckeystore client.p12 -srcstoretype PKCS12 \
    -srcstorepass $KEYSTORE_PASSWORD \
    -alias $ALIAS_CLIENT

# 4. 生成客户端 Truststore (与服务器 Truststore 相同)
echo "4️⃣ 生成客户端 Truststore..."
cp kafka.server.truststore.jks kafka.client.truststore.jks

# 5. 验证 JKS 文件
echo "5️⃣ 验证 JKS 文件..."
echo "服务器 Keystore 内容:"
keytool -list -v -keystore kafka.server.keystore.jks -storepass $KEYSTORE_PASSWORD | grep -E "(Alias name|Valid from|Owner|Issuer)"

echo -e "\n服务器 Truststore 内容:"
keytool -list -v -keystore kafka.server.truststore.jks -storepass $TRUSTSTORE_PASSWORD | grep -E "(Alias name|Valid from|Owner|Issuer)"

echo -e "\n客户端 Keystore 内容:"
keytool -list -v -keystore kafka.client.keystore.jks -storepass $KEYSTORE_PASSWORD | grep -E "(Alias name|Valid from|Owner|Issuer)"

# 6. 备份现有 Secrets
echo "6️⃣ 备份现有 Secrets..."
kubectl get secret kafka-keystore -n confluent-kafka -o yaml > kafka-keystore-backup.yaml
kubectl get secret kafka-tls-certs -n confluent-kafka -o yaml > kafka-tls-certs-backup.yaml
kubectl get secret kafka-client-certs -n opentelemetry -o yaml > kafka-client-certs-backup.yaml 2>/dev/null || echo "kafka-client-certs 不存在，跳过备份"

# 7. 重建 kafka-keystore Secret
echo "7️⃣ 重建 kafka-keystore Secret..."
kubectl delete secret kafka-keystore -n confluent-kafka --ignore-not-found
kubectl create secret generic kafka-keystore -n confluent-kafka \
  --from-file=kafka.server.keystore.jks=kafka.server.keystore.jks \
  --from-file=kafka.server.truststore.jks=kafka.server.truststore.jks \
  --from-literal=keystore.password=$KEYSTORE_PASSWORD \
  --from-literal=truststore.password=$TRUSTSTORE_PASSWORD \
  --from-literal=key.password=$KEY_PASSWORD

# 8. 重建 kafka-tls-certs Secret
echo "8️⃣ 重建 kafka-tls-certs Secret..."
kubectl delete secret kafka-tls-certs -n confluent-kafka --ignore-not-found
kubectl create secret generic kafka-tls-certs -n confluent-kafka \
  --from-file=ca.crt=ca-cert.pem \
  --from-file=server.crt=server-cert.pem \
  --from-file=server.key=server-key.pem \
  --from-file=client.crt=client-cert.pem \
  --from-file=client.key=client-key.pem \
  --from-file=ca.key=ca-key.pem

# 9. 重建 OpenTelemetry 客户端证书 Secret
echo "9️⃣ 重建 OpenTelemetry 客户端证书 Secret..."
kubectl delete secret kafka-client-certs -n opentelemetry --ignore-not-found
kubectl create secret generic kafka-client-certs -n opentelemetry \
  --from-file=ca.crt=ca-cert.pem \
  --from-file=tls.crt=client-cert.pem \
  --from-file=tls.key=client-key.pem \
  --from-file=client.keystore.jks=kafka.client.keystore.jks \
  --from-file=client.truststore.jks=kafka.client.truststore.jks \
  --from-literal=keystore.password=$KEYSTORE_PASSWORD \
  --from-literal=truststore.password=$TRUSTSTORE_PASSWORD \
  --from-literal=key.password=$KEY_PASSWORD

echo "✅ 所有 JKS 文件和 Secrets 更新完成！"
echo "📁 生成的文件:"
ls -la *.jks *.p12

echo -e "\n📋 下一步："
echo "   1. 重启 Kafka StatefulSet:"
echo "      kubectl rollout restart statefulset/kafka -n confluent-kafka"
echo "   2. 等待 Kafka 重启完成:"
echo "      kubectl rollout status statefulset/kafka -n confluent-kafka"
echo "   3. 重启 OpenTelemetry DaemonSet:"
echo "      kubectl rollout restart daemonset/opentelemetry-collector -n opentelemetry"
echo "   4. 验证连接"

echo -e "\n💾 备份文件:"
echo "   - kafka-keystore-backup.yaml"
echo "   - kafka-tls-certs-backup.yaml"
echo "   - kafka-client-certs-backup.yaml"

echo -e "\n🔑 密码信息:"
echo "   - Keystore Password: $KEYSTORE_PASSWORD"
echo "   - Truststore Password: $TRUSTSTORE_PASSWORD"
echo "   - Key Password: $KEY_PASSWORD" 