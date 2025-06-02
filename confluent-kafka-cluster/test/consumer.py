from kafka import KafkaConsumer, KafkaAdminClient
from kafka.admin import NewTopic, ConfigResource, ConfigResourceType
from kafka.errors import TopicAlreadyExistsError, KafkaError
import time
import logging

# 配置日志以显示更多信息
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Kafka 配置
bootstrap_servers = [
    "35.246.19.153:9093",    # kafka-0
    "35.197.245.131:9093",   # kafka-1
    "34.105.181.80:9093"     # kafka-2
]

topic_name = "test_44084750"

# SSL 配置
ssl_config = {
    "security_protocol": "SSL",
    "ssl_cafile": "/Users/stephenzhou/Desktop/workspace/kafka/ha-mtls/k8s/kafka/scripts/opentelemetry/new-certs/ca-cert.crt",
    "ssl_certfile": "/Users/stephenzhou/Desktop/workspace/kafka/ha-mtls/k8s/kafka/scripts/opentelemetry/new-certs/client-cert.crt",
    "ssl_keyfile": "/Users/stephenzhou/Desktop/workspace/kafka/ha-mtls/k8s/kafka/scripts/opentelemetry/new-certs/client-key.key",
    "ssl_check_hostname": False,
    "api_version_auto_timeout_ms": 60000,
}

def create_topic():
    try:
        client_config = {
            "bootstrap_servers": bootstrap_servers,
            "client_id": "admin-client",
            "request_timeout_ms": 60000,
            "retry_backoff_ms": 1000,
            "reconnect_backoff_max_ms": 10000,
            "metadata_max_age_ms": 30000,
            "max_in_flight_requests_per_connection": 5,
            "connections_max_idle_ms": 60000
        }
        client_config.update(ssl_config)
        
        admin = KafkaAdminClient(**client_config)
        
        try:
            topics = admin.list_topics()
            logger.info(f"现有主题列表: {topics}")
            
            if topic_name in topics:
                logger.info(f"主题 '{topic_name}' 已存在")
                try:
                    config_resource = ConfigResource(ConfigResourceType.TOPIC, topic_name)
                    configs = admin.describe_configs([config_resource])
                    if configs and hasattr(configs[0], 'resources'):
                        for resource in configs[0].resources:
                            if hasattr(resource, 'configs'):
                                logger.info(f"主题配置: {resource.configs}")
                except Exception as e:
                    logger.warning(f"获取主题配置失败: {e}")
                return
                
        except Exception as e:
            logger.warning(f"获取主题列表失败: {e}")
            
        new_topic = NewTopic(
            name=topic_name,
            num_partitions=1,
            replication_factor=1,
            topic_configs={
                "min.insync.replicas": 1,
                "unclean.leader.election.enable": True
            }
        )
        
        admin.create_topics(new_topics=[new_topic], validate_only=False)
        logger.info(f"主题 '{topic_name}' 创建成功")
        
    except TopicAlreadyExistsError:
        logger.info(f"主题 '{topic_name}' 已存在")
    except Exception as e:
        logger.error(f"创建主题时出错: {e}")
        raise
    finally:
        if 'admin' in locals():
            admin.close()

def consume_messages():
    try:
        consumer_config = {
            "bootstrap_servers": bootstrap_servers,
            "client_id": "test-consumer",
            "group_id": "test-consumer-group",
            "auto_offset_reset": 'earliest',
            "enable_auto_commit": True,
            "max_poll_records": 100,
            "request_timeout_ms": 60000,
            "session_timeout_ms": 30000,
            "heartbeat_interval_ms": 10000,
            "max_poll_interval_ms": 300000,
            "max_partition_fetch_bytes": 1048576,
            "fetch_max_bytes": 52428800,
            "fetch_min_bytes": 1,
            "fetch_max_wait_ms": 500,
            "retry_backoff_ms": 1000,
            "reconnect_backoff_max_ms": 10000,
            "metadata_max_age_ms": 30000,
        }
        consumer_config.update(ssl_config)
        
        consumer = KafkaConsumer(
            topic_name,
            **consumer_config
        )

        logger.info(f"开始监听主题 '{topic_name}' 的消息...")
        logger.info(f"已连接到 brokers: {', '.join(bootstrap_servers)}")

        try:
            for message in consumer:
                logger.info(f"收到消息: topic={message.topic}, partition={message.partition}, "
                          f"offset={message.offset}, key={message.key}, value={message.value.decode('utf-8')}")
        except KeyboardInterrupt:
            logger.info("用户停止消费")
        except Exception as e:
            logger.error(f"消费消息时出错: {e}")
            raise
        finally:
            consumer.close()
            logger.info("消费者已关闭")
            
    except Exception as e:
        logger.error(f"创建消费者时出错: {e}")
        raise

if __name__ == "__main__":
    try:
        create_topic()
        consume_messages()
    except Exception as e:
        logger.error(f"致命错误: {e}")
        import traceback
        traceback.print_exc()
