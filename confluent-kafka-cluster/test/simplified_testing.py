from kafka import KafkaProducer
import logging

# 启用详细日志
logging.basicConfig(level=logging.DEBUG)

bootstrap_servers = [
    "34.142.35.213:9093"
]

# 首先尝试不使用 SSL 连接（如果服务器支持）
print("🔍 Testing plain connection...")
try:
    producer = KafkaProducer(
        bootstrap_servers=bootstrap_servers,
        request_timeout_ms=10000,
    )
    print("✅ Plain connection successful!")
    producer.close()
except Exception as e:
    print(f"❌ Plain connection failed: {e}")

# 然后测试 SSL 连接
print("\n🔍 Testing SSL connection...")
ssl_config = {
    "security_protocol": "SSL",
    "ssl_cafile": "/Users/stephenzhou/Desktop/workspace/kafka/ha-mtls/k8s/kafka/scripts/opentelemetry/new-certs/ca-cert.pem",
    "ssl_certfile": "/Users/stephenzhou/Desktop/workspace/kafka/ha-mtls/k8s/kafka/scripts/opentelemetry/new-certs/client-cert.pem", 
    "ssl_keyfile": "/Users/stephenzhou/Desktop/workspace/kafka/ha-mtls/k8s/kafka/scripts/opentelemetry/new-certs/client-key.key",
    "ssl_check_hostname": False,
}

try:
    producer = KafkaProducer(
        bootstrap_servers=bootstrap_servers,
        **ssl_config,
        request_timeout_ms=10000,
    )
    print("✅ SSL connection successful!")
    producer.close()
except Exception as e:
    print(f"❌ SSL connection failed: {e}")
    import traceback
    traceback.print_exc()
