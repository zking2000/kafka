#!/bin/bash

# OpenTelemetry Collector Kafka Consumer 部署脚本
# 用于部署连接到mTLS Kafka集群的OTel Collector

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
NAMESPACE="confluent-kafka"
GRAFANA_NAMESPACE="grafana-stack"
DEPLOYMENT_NAME="otelcol-kafka-consumer"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查必要的工具
check_prerequisites() {
    log_info "检查必要的工具和环境"
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl 未安装"
        exit 1
    fi
    
    if ! command -v kustomize &> /dev/null; then
        log_warning "kustomize 未安装，将使用 kubectl apply -k"
    fi
    
    log_success "环境检查完成"
}

# 检查namespace
check_namespaces() {
    log_info "检查必要的命名空间"
    
    if ! kubectl get namespace $NAMESPACE &> /dev/null; then
        log_error "Namespace $NAMESPACE 不存在"
        exit 1
    fi
    
    if ! kubectl get namespace $GRAFANA_NAMESPACE &> /dev/null; then
        log_warning "Namespace $GRAFANA_NAMESPACE 不存在，请确保Grafana Stack已部署"
    fi
    
    log_success "命名空间检查完成"
}

# 检查依赖
check_dependencies() {
    log_info "检查依赖服务"
    
    # 检查Kafka集群
    if ! kubectl get pods -n $NAMESPACE -l app=kafka --no-headers | grep -q "Running"; then
        log_error "Kafka集群未运行"
        exit 1
    fi
    
    # 检查SSL证书Secret
    if ! kubectl get secret kafka-ssl-certs -n $NAMESPACE &> /dev/null; then
        log_error "Kafka SSL证书Secret不存在"
        exit 1
    fi
    
    log_success "依赖检查完成"
}

# 在Pod内创建客户端配置文件
create_kafka_client_config() {
    log_info "在Kafka Pod内创建客户端配置文件"
    
    # 检查凭据文件是否存在
    local creds_check=$(kubectl exec kafka-0 -n $NAMESPACE -- \
        sh -c 'if [ -f /etc/kafka/secrets/keystore_creds ]; then echo "exists"; else echo "missing"; fi' 2>/dev/null)
    
    if [ "$creds_check" = "missing" ]; then
        log_info "凭据文件不存在，使用直接密码方式创建配置"
        
        # 从Secret获取密码
        local KEYSTORE_PASSWORD=$(kubectl get secret kafka-ssl-certs -n $NAMESPACE -o jsonpath="{.data.keystore\.password}" 2>/dev/null | base64 -d 2>/dev/null)
        local KEY_PASSWORD=$(kubectl get secret kafka-ssl-certs -n $NAMESPACE -o jsonpath="{.data.key\.password}" 2>/dev/null | base64 -d 2>/dev/null)
        local TRUSTSTORE_PASSWORD=$(kubectl get secret kafka-ssl-certs -n $NAMESPACE -o jsonpath="{.data.truststore\.password}" 2>/dev/null | base64 -d 2>/dev/null)
        
        if [ -z "$KEYSTORE_PASSWORD" ] || [ -z "$KEY_PASSWORD" ] || [ -z "$TRUSTSTORE_PASSWORD" ]; then
            log_error "无法从Secret获取密码"
            return 1
        fi
        
        # 在Pod内创建配置文件，直接使用密码
        kubectl exec kafka-0 -n $NAMESPACE -- sh -c "
            cat > /tmp/client.properties << EOF
security.protocol=SSL
ssl.keystore.location=/etc/kafka/secrets/kafka.server.keystore.jks
ssl.keystore.password=$KEYSTORE_PASSWORD
ssl.key.password=$KEY_PASSWORD
ssl.truststore.location=/etc/kafka/secrets/kafka.server.truststore.jks
ssl.truststore.password=$TRUSTSTORE_PASSWORD
ssl.endpoint.identification.algorithm=
ssl.client.auth=required
bootstrap.servers=localhost:9092
EOF
        " 2>/dev/null
    else
        # 在Pod内创建配置文件，使用凭据文件
        kubectl exec kafka-0 -n $NAMESPACE -- sh -c "
            cat > /tmp/client.properties << EOF
security.protocol=SSL
ssl.keystore.location=/etc/kafka/secrets/kafka.server.keystore.jks
ssl.keystore.password=\$(cat /etc/kafka/secrets/keystore_creds)
ssl.key.password=\$(cat /etc/kafka/secrets/key_creds)
ssl.truststore.location=/etc/kafka/secrets/kafka.server.truststore.jks
ssl.truststore.password=\$(cat /etc/kafka/secrets/truststore_creds)
ssl.endpoint.identification.algorithm=
ssl.client.auth=required
bootstrap.servers=localhost:9092
EOF
        " 2>/dev/null
    fi
    
    if [ $? -eq 0 ]; then
        log_success "客户端配置文件创建成功"
        return 0
    else
        log_error "客户端配置文件创建失败"
        return 1
    fi
}

# 创建Kafka topics
create_topics() {
    log_info "创建必要的Kafka Topics"
    
    # 首先创建客户端配置文件
    if ! create_kafka_client_config; then
        log_error "无法创建Kafka客户端配置，跳过Topic创建"
        return 1
    fi
    
    local topics=("otcol_logs" "otcol_metrics" "otcol_traces")
    
    for topic in "${topics[@]}"; do
        log_info "检查Topic: $topic"
        
        # 检查topic是否存在
        local topic_exists=$(kubectl exec kafka-0 -n $NAMESPACE -- \
            env JMX_PORT= kafka-topics --list \
            --bootstrap-server localhost:9092 \
            --command-config /tmp/client.properties 2>/dev/null | \
            grep "^$topic$" || echo "")
        
        if [ -z "$topic_exists" ]; then
            log_info "创建Topic: $topic"
            local create_output=$(kubectl exec kafka-0 -n $NAMESPACE -- \
                env JMX_PORT= kafka-topics --create --topic $topic \
                --bootstrap-server localhost:9092 \
                --replication-factor 3 \
                --partitions 6 \
                --command-config /tmp/client.properties 2>&1)
            
            if [ $? -eq 0 ]; then
                log_success "Topic $topic 创建成功"
            else
                log_error "Topic $topic 创建失败: $create_output"
                # 检查是否因为已存在而失败
                if echo "$create_output" | grep -q "already exists"; then
                    log_warning "Topic $topic 已存在，继续执行"
                else
                    log_error "Topic创建失败，请检查Kafka集群状态"
                    return 1
                fi
            fi
        else
            log_success "Topic $topic 已存在"
        fi
    done
    
    # 验证所有topics都已创建
    log_info "验证所有Topics状态"
    local all_topics=$(kubectl exec kafka-0 -n $NAMESPACE -- \
        env JMX_PORT= kafka-topics --list \
        --bootstrap-server localhost:9092 \
        --command-config /tmp/client.properties 2>/dev/null)
    
    for topic in "${topics[@]}"; do
        if echo "$all_topics" | grep -q "^$topic$"; then
            log_success "✓ Topic $topic 验证通过"
        else
            log_error "✗ Topic $topic 验证失败"
            return 1
        fi
    done
    
    # 清理临时配置文件
    kubectl exec kafka-0 -n $NAMESPACE -- rm -f /tmp/client.properties &> /dev/null || true
    
    log_success "所有Topics创建和验证完成"
}

# 部署OTel Collector
deploy_collector() {
    log_info "部署OpenTelemetry Collector"
    
    # 使用kustomize部署
    if kubectl apply -k . -n $NAMESPACE; then
        log_success "OpenTelemetry Collector部署成功"
    else
        log_error "部署失败"
        exit 1
    fi
    
    # 等待Pod就绪
    log_info "等待Pod就绪..."
    if kubectl wait --for=condition=ready pod -l app=otelcol -n $NAMESPACE --timeout=300s; then
        log_success "所有Pod已就绪"
    else
        log_error "Pod未在规定时间内就绪"
        exit 1
    fi
}

# 验证部署
verify_deployment() {
    log_info "验证部署状态"
    
    # 检查Pod状态
    local pod_count=$(kubectl get pods -n $NAMESPACE -l app=otelcol --no-headers | wc -l)
    local running_pods=$(kubectl get pods -n $NAMESPACE -l app=otelcol --no-headers | grep "Running" | wc -l)
    
    log_info "Pod状态: $running_pods/$pod_count 运行中"
    
    # 检查健康状态
    local health_check=$(kubectl get pods -n $NAMESPACE -l app=otelcol -o name | head -1 | xargs -I {} kubectl exec {} -n $NAMESPACE -- wget -qO- http://localhost:13133/health || echo "unhealthy")
    
    if [ "$health_check" = "unhealthy" ]; then
        log_warning "健康检查失败，请检查日志"
    else
        log_success "健康检查通过"
    fi
    
    # 显示服务信息
    log_info "服务信息:"
    kubectl get svc -n $NAMESPACE -l app=otelcol
}

# 清理部署
cleanup() {
    log_info "清理OpenTelemetry Collector部署"
    
    if kubectl delete -k . -n $NAMESPACE; then
        log_success "清理完成"
    else
        log_error "清理失败"
        exit 1
    fi
}

# 显示日志
show_logs() {
    log_info "显示OpenTelemetry Collector日志"
    kubectl logs -n $NAMESPACE -l app=otelcol --tail=100 -f
}

# 测试Kafka连接
test_kafka_connection() {
    log_info "测试Kafka连接"
    
    if ! create_kafka_client_config; then
        log_error "无法创建Kafka客户端配置"
        return 1
    fi
    
    # 测试连接并列出topics
    log_info "尝试连接Kafka并列出topics"
    local topics_list=$(kubectl exec kafka-0 -n $NAMESPACE -- \
        env JMX_PORT= kafka-topics --list \
        --bootstrap-server localhost:9092 \
        --command-config /tmp/client.properties 2>&1)
    
    if [ $? -eq 0 ]; then
        log_success "Kafka连接成功"
        log_info "当前存在的Topics:"
        echo "$topics_list" | sed 's/^/  - /'
        
        # 检查OTel相关topics
        local otel_topics=("otcol_logs" "otcol_metrics" "otcol_traces")
        log_info "检查OpenTelemetry相关Topics:"
        for topic in "${otel_topics[@]}"; do
            if echo "$topics_list" | grep -q "^$topic$"; then
                log_success "  ✓ $topic 存在"
            else
                log_warning "  ✗ $topic 不存在"
            fi
        done
    else
        log_error "Kafka连接失败"
        log_error "错误详情: $topics_list"
        return 1
    fi
    
    # 清理临时配置文件
    kubectl exec kafka-0 -n $NAMESPACE -- rm -f /tmp/client.properties &> /dev/null || true
}

# 显示帮助
show_help() {
    echo "OpenTelemetry Collector Kafka Consumer 部署脚本"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "命令:"
    echo "  deploy      部署OTel Collector (默认)"
    echo "  cleanup     清理部署"
    echo "  verify      验证部署状态"
    echo "  logs        显示日志"
    echo "  topics      创建Kafka Topics"
    echo "  test-kafka  测试Kafka连接和Topics状态"
    echo "  help        显示帮助"
    echo ""
    echo "示例:"
    echo "  $0 deploy       # 完整部署collector"
    echo "  $0 topics       # 仅创建topics"
    echo "  $0 test-kafka   # 测试Kafka连接"
    echo "  $0 cleanup      # 清理部署"
    echo "  $0 logs         # 查看日志"
    echo ""
    echo "Topic创建说明:"
    echo "  脚本会自动连接到kafka-0 Pod，创建以下Topics:"
    echo "    - otcol_logs     (分区:6, 副本:3) → Loki"
    echo "    - otcol_metrics  (分区:6, 副本:3) → Mimir"
    echo "    - otcol_traces   (分区:6, 副本:3) → Tempo"
}

# 主函数
main() {
    case "${1:-deploy}" in
        "deploy")
            log_info "开始完整部署流程"
            check_prerequisites
            check_namespaces
            check_dependencies
            create_topics
            deploy_collector
            verify_deployment
            log_success "部署流程完成"
            ;;
        "cleanup")
            cleanup
            ;;
        "verify")
            verify_deployment
            ;;
        "logs")
            show_logs
            ;;
        "topics")
            log_info "开始创建Kafka Topics"
            check_prerequisites
            check_namespaces
            check_dependencies
            create_topics
            log_success "Topics创建流程完成"
            ;;
        "test-kafka"|"test")
            log_info "开始测试Kafka连接"
            check_prerequisites
            check_namespaces
            check_dependencies
            test_kafka_connection
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log_error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@" 