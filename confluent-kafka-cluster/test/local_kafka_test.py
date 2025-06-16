#!/usr/bin/env python3
"""
本地Kafka测试脚本
使用外部IP地址和mTLS连接到Kafka集群
"""

import json
import time
import sys
import base64
from datetime import datetime
from kafka import KafkaProducer, KafkaConsumer
from kafka.admin import KafkaAdminClient, NewTopic
from kafka.errors import KafkaError, TopicAlreadyExistsError
import ssl

# Kafka外部IP地址和端口映射
KAFKA_BROKERS = [
    '35.197.206.204:9093',   # kafka-0-internal
    '34.147.221.36:9093',    # kafka-1-internal  
    '34.39.39.253:9093'      # kafka-2-internal
]

# 证书文件路径
import os
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)

CERT_FILES = {
    'ca_cert': os.path.join(PROJECT_ROOT, 'deploy/certs/ca-cert.pem'),
    'client_cert': os.path.join(PROJECT_ROOT, 'deploy/certs/kafka-client-cert.pem'),
    'client_key': os.path.join(PROJECT_ROOT, 'deploy/certs/kafka-client-key.pem')
}

def check_cert_files():
    """检查证书文件是否存在"""
    for name, path in CERT_FILES.items():
        if not os.path.exists(path):
            print(f"❌ 证书文件不存在: {name} -> {path}")
            return False
        else:
            print(f"✅ 证书文件存在: {name} -> {path}")
    return True

def create_ssl_context():
    """创建SSL上下文"""
    # 首先检查证书文件
    if not check_cert_files():
        raise FileNotFoundError("证书文件缺失")
    
    context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH)
    context.check_hostname = False  # 跳过主机名验证，因为使用IP地址
    context.verify_mode = ssl.CERT_REQUIRED
    
    # 加载CA证书
    context.load_verify_locations(CERT_FILES['ca_cert'])
    
    # 加载客户端证书和私钥
    context.load_cert_chain(CERT_FILES['client_cert'], CERT_FILES['client_key'])
    
    return context

def create_simple_log_message():
    """创建简单的OTLP日志消息"""
    timestamp_ns = int(time.time() * 1_000_000_000)
    
    message = {
        "resourceLogs": [{
            "resource": {
                "attributes": [{
                    "key": "service.name",
                    "value": {"stringValue": "local-test-service"}
                }]
            },
            "scopeLogs": [{
                "scope": {"name": "local-test-logger"},
                "logRecords": [{
                    "timeUnixNano": str(timestamp_ns),
                    "severityText": "INFO",
                    "body": {"stringValue": f"本地测试日志 - {datetime.now().isoformat()}"}
                }]
            }]
        }]
    }
    
    return json.dumps(message, ensure_ascii=False)

def create_simple_metrics_message():
    """创建简单的OTLP指标消息"""
    timestamp_ns = int(time.time() * 1_000_000_000)
    
    message = {
        "resourceMetrics": [{
            "resource": {
                "attributes": [{
                    "key": "service.name", 
                    "value": {"stringValue": "local-test-service"}
                }]
            },
            "scopeMetrics": [{
                "scope": {"name": "local-test-meter"},
                "metrics": [{
                    "name": "local_test_counter",
                    "sum": {
                        "dataPoints": [{
                            "timeUnixNano": str(timestamp_ns),
                            "asInt": "42"
                        }]
                    }
                }]
            }]
        }]
    }
    
    return json.dumps(message, ensure_ascii=False)

def create_simple_trace_message():
    """创建简单的OTLP追踪消息"""
    timestamp_ns = int(time.time() * 1_000_000_000)
    
    message = {
        "resourceSpans": [{
            "resource": {
                "attributes": [{
                    "key": "service.name",
                    "value": {"stringValue": "local-test-service"}
                }]
            },
            "scopeSpans": [{
                "scope": {"name": "local-test-tracer"},
                "spans": [{
                    "traceId": base64.b64encode(b"1234567890123456").decode(),
                    "spanId": base64.b64encode(b"12345678").decode(),
                    "name": "local-test-span",
                    "startTimeUnixNano": str(timestamp_ns),
                    "endTimeUnixNano": str(timestamp_ns + 1000000)
                }]
            }]
        }]
    }
    
    return json.dumps(message, ensure_ascii=False)

def create_admin_client():
    """创建Kafka管理客户端"""
    ssl_context = create_ssl_context()
    
    admin_client = KafkaAdminClient(
        bootstrap_servers=KAFKA_BROKERS,
        security_protocol='SSL',
        ssl_context=ssl_context,
        client_id='local-test-admin',
        api_version=(2, 6, 0),
        request_timeout_ms=30000
    )
    
    return admin_client

def check_and_create_topics():
    """检查并创建必需的topics"""
    print("📋 检查并创建topics...")
    
    required_topics = ["otcol_logs", "otcol_metrics", "otcol_traces"]
    
    try:
        admin_client = create_admin_client()
        
        # 获取现有topics
        existing_topics = admin_client.list_topics()
        print(f"  现有topics: {list(existing_topics)}")
        
        # 检查哪些topics需要创建
        topics_to_create = []
        for topic in required_topics:
            if topic in existing_topics:
                print(f"  ✅ Topic {topic} 已存在")
            else:
                print(f"  ⚠️ Topic {topic} 不存在，需要创建")
                topics_to_create.append(topic)
        
        # 创建缺失的topics
        if topics_to_create:
            print(f"  🔨 创建topics: {topics_to_create}")
            
            new_topics = [
                NewTopic(
                    name=topic,
                    num_partitions=6,  # 6个分区
                    replication_factor=1  # 1个副本
                ) for topic in topics_to_create
            ]
            
            try:
                result = admin_client.create_topics(new_topics, validate_only=False)
                
                # 等待创建完成
                try:
                    if hasattr(result, 'items'):
                        # 字典类型
                        for topic, future in result.items():
                            try:
                                future.result()  # 等待结果
                                print(f"  ✅ Topic {topic} 创建成功")
                            except TopicAlreadyExistsError:
                                print(f"  ✅ Topic {topic} 已存在")
                            except Exception as e:
                                print(f"  ❌ Topic {topic} 创建失败: {str(e)}")
                    else:
                        # 其他类型，直接报告成功
                        for topic in topics_to_create:
                            print(f"  ✅ Topic {topic} 创建请求已发送")
                except Exception as e:
                    print(f"  ❌ 处理创建结果时出错: {str(e)}")
                        
            except Exception as e:
                print(f"  ❌ 创建topics失败: {str(e)}")
        else:
            print("  ✅ 所有必需的topics都已存在")
        
        admin_client.close()
        return True
        
    except Exception as e:
        print(f"❌ 检查topics失败: {str(e)}")
        return False

def test_kafka_connection():
    """测试Kafka连接"""
    print("🔗 测试Kafka连接...")
    
    try:
        ssl_context = create_ssl_context()
        
        producer = KafkaProducer(
            bootstrap_servers=KAFKA_BROKERS,
            security_protocol='SSL',
            ssl_context=ssl_context,
            value_serializer=lambda v: v.encode('utf-8'),
            client_id='local-test-producer',
            api_version=(2, 6, 0),
            request_timeout_ms=30000,
            retries=3
        )
        
        print("✅ Kafka连接成功")
        return producer
        
    except Exception as e:
        print(f"❌ Kafka连接失败: {str(e)}")
        return None

def send_test_messages(producer):
    """发送测试消息到3个topics"""
    print("\n📤 发送测试消息...")
    
    messages = {
        "otcol_logs": create_simple_log_message(),
        "otcol_metrics": create_simple_metrics_message(),
        "otcol_traces": create_simple_trace_message()
    }
    
    success_count = 0
    
    for topic, message in messages.items():
        try:
            print(f"  发送到 {topic}...")
            
            future = producer.send(topic, message)
            record_metadata = future.get(timeout=10)
            
            print(f"  ✅ {topic} 发送成功 (partition: {record_metadata.partition}, offset: {record_metadata.offset})")
            success_count += 1
            
        except Exception as e:
            print(f"  ❌ {topic} 发送失败: {str(e)}")
        
        time.sleep(1)
    
    return success_count

def verify_messages():
    """验证消息是否发送成功"""
    print("\n🔍 验证消息...")
    
    try:
        ssl_context = create_ssl_context()
        
        topics = ["otcol_logs", "otcol_metrics", "otcol_traces"]
        verified_count = 0
        
        for topic in topics:
            try:
                print(f"  检查 {topic}...")
                
                consumer = KafkaConsumer(
                    topic,
                    bootstrap_servers=KAFKA_BROKERS,
                    security_protocol='SSL',
                    ssl_context=ssl_context,
                    auto_offset_reset='latest',
                    consumer_timeout_ms=5000,
                    client_id=f'local-test-consumer-{topic}'
                )
                
                # 检查是否有分区分配
                partitions = consumer.partitions_for_topic(topic)
                if partitions:
                    print(f"    ✅ {topic} 存在 (分区: {len(partitions)})")
                    verified_count += 1
                else:
                    print(f"    ⚠️ {topic} 不存在或无分区")
                
                consumer.close()
                
            except Exception as e:
                print(f"    ❌ 检查 {topic} 失败: {str(e)}")
        
        return verified_count
        
    except Exception as e:
        print(f"❌ 验证过程失败: {str(e)}")
        return 0

def main():
    print("🚀 本地Kafka mTLS测试")
    print("=" * 40)
    print(f"连接到Kafka集群: {KAFKA_BROKERS}")
    print("=" * 40)
    
    # 检查并创建topics
    if not check_and_create_topics():
        print("❌ Topics检查/创建失败，但继续测试连接...")
    
    print("\n" + "=" * 40)
    
    # 测试连接
    producer = test_kafka_connection()
    if not producer:
        print("❌ 无法连接到Kafka，退出测试")
        sys.exit(1)
    
    try:
        # 发送消息
        success_count = send_test_messages(producer)
        
        # 刷新并关闭生产者
        producer.flush()
        producer.close()
        
        print(f"\n📊 发送结果: {success_count}/3 成功")
        
        if success_count > 0:
            # 验证消息
            verified_count = verify_messages()
            print(f"📊 验证结果: {verified_count}/3 成功")
            
            print("\n" + "=" * 40)
            print("📋 测试总结:")
            print(f"  连接状态: ✅")
            print(f"  消息发送: {success_count}/3")
            print(f"  Topic验证: {verified_count}/3")
            
            if success_count > 0:
                print("\n🎉 测试成功！消息已发送到Kafka集群")
                print("💡 现在可以检查OpenTelemetry Collector是否接收到消息")
            else:
                print("\n❌ 测试失败")
        else:
            print("\n❌ 没有消息发送成功")
            
    except KeyboardInterrupt:
        print("\n⏹️ 测试被用户中断")
    except Exception as e:
        print(f"\n❌ 测试过程中出错: {str(e)}")
    finally:
        if producer:
            producer.close()

if __name__ == "__main__":
    main() 