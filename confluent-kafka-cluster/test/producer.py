from kafka import KafkaProducer, KafkaAdminClient
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

# 外部访问地址
bootstrap_servers = [
    "35.246.19.153:9093",    # kafka-0
    "35.197.245.131:9093",   # kafka-1
    "34.105.181.80:9093"     # kafka-2
]

topic_name = "test_44084750"

ssl_config = {
    "security_protocol": "SSL",
    "ssl_cafile": "../deploy/certs/ca-cert.pem",
    "ssl_certfile": "../deploy/certs/kafka-client-cert.pem",
    "ssl_keyfile": "../deploy/certs/kafka-client-key.pem",
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
                logger.info(f"主题 '{topic_name}' 已存在，检查配置...")
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
            replication_factor=1,  # 整数类型
            topic_configs={
                "min.insync.replicas": 1,  # 整数类型
                "unclean.leader.election.enable": True  # 布尔类型
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

def send_messages():
    try:
        producer_config = {
            "bootstrap_servers": bootstrap_servers,
            "client_id": "test-producer",
            "acks": 1,                      # 整数类型
            "max_in_flight_requests_per_connection": 5,
            "request_timeout_ms": 60000,
            "delivery_timeout_ms": 120000,
            "retries": 5,
            "retry_backoff_ms": 1000,
            "reconnect_backoff_max_ms": 10000,
            "value_serializer": lambda v: v.encode('utf-8'),
            "max_block_ms": 60000,
            "metadata_max_age_ms": 30000,
        }
        producer_config.update(ssl_config)
        
        producer = KafkaProducer(**producer_config)
        
        logger.info("开始发送消息...")
        logger.info(f"已连接到 brokers: {', '.join(bootstrap_servers)}")
        
        for i in range(100):
            message = f"Hello Kafka {i}"
            try:
                future = producer.send(topic_name, message)
                result = future.get(timeout=30)
                logger.info(f"消息 {i} 发送成功: {message} -> 分区: {result.partition}, 偏移量: {result.offset}")
                producer.flush()
            except KafkaError as e:
                logger.error(f"消息 {i} 发送失败: {e}")
            except Exception as e:
                logger.error(f"发送消息 {i} 时出现意外错误: {e}")
            
            time.sleep(1)
        
        producer.flush()
        logger.info("所有消息发送完成!")
        
    except Exception as e:
        logger.error(f"生产者错误: {e}")
        raise
    finally:
        if 'producer' in locals():
            producer.close()

if __name__ == "__main__":
    try:
        create_topic()
        send_messages()
    except Exception as e:
        logger.error(f"致命错误: {e}")
        import traceback
        traceback.print_exc()
