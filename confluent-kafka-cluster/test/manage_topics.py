#!/usr/bin/env python3
"""
Kafka Topic管理脚本 - 通过外部接口直接操作
"""

import os
import sys
import ssl
import argparse
from kafka.admin import KafkaAdminClient, NewTopic
from kafka.errors import TopicAlreadyExistsError

# Kafka外部IP地址
KAFKA_BROKERS = [
    '35.197.206.204:9093',   # kafka-0-internal
    '34.147.221.36:9093',    # kafka-1-internal  
    '34.39.39.253:9093'      # kafka-2-internal
]

# 证书文件路径
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)

CERT_FILES = {
    'ca_cert': os.path.join(PROJECT_ROOT, 'deploy/certs/ca-cert.pem'),
    'client_cert': os.path.join(PROJECT_ROOT, 'deploy/certs/kafka-client-cert.pem'),
    'client_key': os.path.join(PROJECT_ROOT, 'deploy/certs/kafka-client-key.pem')
}

def create_admin_client():
    """创建Kafka管理客户端"""
    context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_REQUIRED
    context.load_verify_locations(CERT_FILES['ca_cert'])
    context.load_cert_chain(CERT_FILES['client_cert'], CERT_FILES['client_key'])
    
    return KafkaAdminClient(
        bootstrap_servers=KAFKA_BROKERS,
        security_protocol='SSL',
        ssl_context=context,
        client_id='topic-manager',
        api_version=(2, 6, 0),
        request_timeout_ms=30000
    )

def list_topics():
    """列出所有topics"""
    print("📋 当前Kafka集群中的topics:")
    try:
        admin_client = create_admin_client()
        topics = admin_client.list_topics()
        
        for topic in sorted(topics):
            if not topic.startswith('__'):  # 过滤内部topics
                print(f"  ✅ {topic}")
        
        admin_client.close()
        return list(topics)
        
    except Exception as e:
        print(f"❌ 获取topics失败: {str(e)}")
        return []

def create_topic(topic_name, partitions=6, replication_factor=1):
    """创建topic"""
    print(f"🔨 创建topic: {topic_name}")
    
    try:
        admin_client = create_admin_client()
        
        # 检查topic是否已存在
        existing_topics = admin_client.list_topics()
        if topic_name in existing_topics:
            print(f"⚠️ Topic '{topic_name}' 已存在")
            admin_client.close()
            return True
        
        # 创建新topic
        new_topic = NewTopic(
            name=topic_name,
            num_partitions=partitions,
            replication_factor=replication_factor
        )
        
        admin_client.create_topics([new_topic], validate_only=False)
        print(f"✅ Topic '{topic_name}' 创建成功")
        
        admin_client.close()
        return True
        
    except Exception as e:
        print(f"❌ 创建topic失败: {str(e)}")
        return False

def delete_topic(topic_name):
    """删除topic"""
    print(f"🗑️ 删除topic: {topic_name}")
    
    try:
        admin_client = create_admin_client()
        
        # 检查topic是否存在
        existing_topics = admin_client.list_topics()
        if topic_name not in existing_topics:
            print(f"⚠️ Topic '{topic_name}' 不存在")
            admin_client.close()
            return True
        
        # 删除topic
        admin_client.delete_topics([topic_name])
        print(f"✅ Topic '{topic_name}' 删除成功")
        
        admin_client.close()
        return True
        
    except Exception as e:
        print(f"❌ 删除topic失败: {str(e)}")
        return False

def ensure_required_topics():
    """确保必需的topics存在"""
    required_topics = ["otcol_logs", "otcol_metrics", "otcol_traces"]
    
    print("🔍 检查必需的topics...")
    
    try:
        admin_client = create_admin_client()
        existing_topics = admin_client.list_topics()
        
        topics_to_create = []
        for topic in required_topics:
            if topic in existing_topics:
                print(f"  ✅ {topic} 已存在")
            else:
                print(f"  ⚠️ {topic} 不存在，需要创建")
                topics_to_create.append(topic)
        
        # 创建缺失的topics
        if topics_to_create:
            print(f"🔨 创建缺失的topics: {topics_to_create}")
            
            new_topics = [
                NewTopic(name=topic, num_partitions=6, replication_factor=1)
                for topic in topics_to_create
            ]
            
            admin_client.create_topics(new_topics, validate_only=False)
            
            for topic in topics_to_create:
                print(f"  ✅ {topic} 创建成功")
        else:
            print("✅ 所有必需的topics都已存在")
        
        admin_client.close()
        return True
        
    except Exception as e:
        print(f"❌ 检查/创建topics失败: {str(e)}")
        return False

def main():
    parser = argparse.ArgumentParser(description='Kafka Topic管理工具')
    parser.add_argument('action', choices=['list', 'create', 'delete', 'ensure'], 
                       help='操作类型: list(列出), create(创建), delete(删除), ensure(确保必需topics存在)')
    parser.add_argument('--topic', help='Topic名称 (create/delete时必需)')
    parser.add_argument('--partitions', type=int, default=6, help='分区数 (默认: 6)')
    parser.add_argument('--replication-factor', type=int, default=1, help='副本因子 (默认: 1)')
    
    args = parser.parse_args()
    
    print("🚀 Kafka Topic管理工具")
    print(f"连接到: {KAFKA_BROKERS}")
    print("=" * 50)
    
    if args.action == 'list':
        list_topics()
        
    elif args.action == 'create':
        if not args.topic:
            print("❌ 创建topic需要指定 --topic 参数")
            sys.exit(1)
        create_topic(args.topic, args.partitions, args.replication_factor)
        
    elif args.action == 'delete':
        if not args.topic:
            print("❌ 删除topic需要指定 --topic 参数")
            sys.exit(1)
        
        # 安全确认
        confirm = input(f"⚠️ 确定要删除topic '{args.topic}'? (yes/N): ").strip().lower()
        if confirm == 'yes':
            delete_topic(args.topic)
        else:
            print("取消删除操作")
            
    elif args.action == 'ensure':
        ensure_required_topics()

if __name__ == "__main__":
    main() 