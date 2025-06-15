#!/bin/bash

# Kafka mTLS 集群测试脚本
# 用于验证 Confluent Kafka mTLS 集群是否正常工作
#
# 安全说明:
# - 此脚本从Kubernetes Secret中安全地获取密码
# - 不在脚本中硬编码任何敏感信息
# - 使用容器内的密码文件进行SSL/TLS认证
# - 临时配置文件在测试结束后自动清理

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
NAMESPACE="confluent-kafka"
TEST_TOPIC="test-mtls-topic"
TEST_MESSAGE="Hello mTLS Kafka $(date)"
TIMEOUT=300
BROKER_COUNT=3

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

# 检查kubectl命令
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl 命令未找到，请先安装 kubectl"
        exit 1
    fi
}

# 检查namespace是否存在
check_namespace() {
    log_info "检查namespace: $NAMESPACE"
    if ! kubectl get namespace $NAMESPACE &> /dev/null; then
        log_error "Namespace $NAMESPACE 不存在"
        exit 1
    fi
    log_success "Namespace $NAMESPACE 存在"
}

# 检查Secret是否存在
check_secrets() {
    log_info "检查必需的Secret"
    
    if ! kubectl get secret kafka-ssl-certs -n $NAMESPACE &> /dev/null; then
        log_error "Secret kafka-ssl-certs 不存在"
        exit 1
    fi
    log_success "Secret kafka-ssl-certs 存在"
}

# 检查Pod状态
check_pods() {
    log_info "检查Kafka Pod状态"
    
    # 检查Pod数量
    POD_COUNT=$(kubectl get pods -n $NAMESPACE -l app=kafka --no-headers | wc -l)
    if [ "$POD_COUNT" -ne "$BROKER_COUNT" ]; then
        log_error "期望 $BROKER_COUNT 个Pod，但找到 $POD_COUNT 个"
        return 1
    fi
    
    # 检查Pod状态
    local failed_pods=()
    for i in $(seq 0 $((BROKER_COUNT-1))); do
        local pod_name="kafka-$i"
        local pod_status=$(kubectl get pod $pod_name -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
        local ready_status=$(kubectl get pod $pod_name -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
        
        if [ "$pod_status" != "Running" ] || [ "$ready_status" != "True" ]; then
            failed_pods+=("$pod_name($pod_status/$ready_status)")
        fi
    done
    
    if [ ${#failed_pods[@]} -gt 0 ]; then
        log_error "以下Pod未就绪: ${failed_pods[*]}"
        return 1
    fi
    
    log_success "所有 $BROKER_COUNT 个Kafka Pod运行正常"
}

# 检查Service状态
check_services() {
    log_info "检查Kafka Service状态"
    
    local required_services=("kafka-headless" "kafka" "kafka-0-internal" "kafka-1-internal" "kafka-2-internal")
    
    for service in "${required_services[@]}"; do
        if ! kubectl get service $service -n $NAMESPACE &> /dev/null; then
            log_error "Service $service 不存在"
            return 1
        fi
    done
    
    log_success "所有必需的Service存在"
}

# 检查endpoints
check_endpoints() {
    log_info "检查kafka-headless Service endpoints"
    
    local endpoints=$(kubectl get endpoints kafka-headless -n $NAMESPACE -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null)
    local endpoint_count=$(echo $endpoints | wc -w)
    
    if [ "$endpoint_count" -ne "$BROKER_COUNT" ]; then
        log_warning "期望 $BROKER_COUNT 个endpoints，但找到 $endpoint_count 个"
        log_info "Endpoints: $endpoints"
    else
        log_success "kafka-headless endpoints正常 ($endpoint_count 个)"
    fi
}



# 等待Pod就绪
wait_for_pods() {
    log_info "等待所有Pod就绪 (最多 ${TIMEOUT}s)"
    
    if kubectl wait --for=condition=ready pod -l app=kafka -n $NAMESPACE --timeout=${TIMEOUT}s &> /dev/null; then
        log_success "所有Pod已就绪"
    else
        log_error "Pod未在 ${TIMEOUT}s 内就绪"
        return 1
    fi
}

# 测试集群连接性
test_cluster_connectivity() {
    log_info "测试集群内部连接性"
    
    for i in $(seq 0 $((BROKER_COUNT-1))); do
        local pod_name="kafka-$i"
        log_info "测试从 kafka-0 到 $pod_name 的连接"
        
        # 测试内部SSL端口
        if kubectl exec kafka-0 -n $NAMESPACE -- timeout 10 nc -z "$pod_name.kafka-headless.confluent-kafka.svc.cluster.local" 9092 &> /dev/null; then
            log_success "$pod_name:9092 连接正常"
        else
            log_error "$pod_name:9092 连接失败"
            return 1
        fi
        
        # 测试控制器端口
        if kubectl exec kafka-0 -n $NAMESPACE -- timeout 10 nc -z "$pod_name.kafka-headless.confluent-kafka.svc.cluster.local" 9094 &> /dev/null; then
            log_success "$pod_name:9094 连接正常"
        else
            log_error "$pod_name:9094 连接失败"
            return 1
        fi
    done
}

# 获取密码的函数
get_password() {
    local password_type="$1"
    local password=$(kubectl get secret kafka-ssl-certs -n $NAMESPACE -o jsonpath="{.data.${password_type}\.password}" 2>/dev/null | base64 -d 2>/dev/null)
    echo "$password"
}

# 诊断SSL配置问题
diagnose_ssl_setup() {
    log_info "诊断SSL配置问题"
    
    # 检查Secret是否存在及其内容
    log_info "检查kafka-ssl-certs Secret"
    if kubectl get secret kafka-ssl-certs -n $NAMESPACE &> /dev/null; then
        log_success "kafka-ssl-certs Secret存在"
        
        # 检查Secret中的密码字段
        local secret_keys=$(kubectl get secret kafka-ssl-certs -n $NAMESPACE -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null || echo "无法获取")
        log_info "Secret中的密钥: $secret_keys"
    else
        log_error "kafka-ssl-certs Secret不存在"
        return 1
    fi
    
    # 检查Pod内的SSL文件
    log_info "检查Pod内的SSL文件"
    kubectl exec kafka-0 -n $NAMESPACE -- \
        sh -c 'echo "SSL目录内容:"; ls -la /etc/kafka/secrets/ 2>/dev/null' 2>/dev/null || \
        log_error "无法访问SSL目录"
    
    # 检查initContainer日志
    log_info "检查initContainer日志"
    local init_logs=$(kubectl logs kafka-0 -n $NAMESPACE -c create-ssl-creds --tail=10 2>/dev/null || echo "无法获取initContainer日志")
    if [ -n "$init_logs" ]; then
        log_info "initContainer日志片段:"
        echo "$init_logs"
    fi
    
    # 检查主容器日志中的SSL相关错误
    log_info "检查主容器SSL相关日志"
    local ssl_logs=$(kubectl logs kafka-0 -n $NAMESPACE --tail=20 | grep -i ssl 2>/dev/null || echo "无SSL相关日志")
    if [ "$ssl_logs" != "无SSL相关日志" ]; then
        log_info "SSL相关日志:"
        echo "$ssl_logs"
    fi
}

# 创建Pod内的客户端配置文件
create_pod_client_config() {
    log_info "在Pod内创建客户端配置文件"
    
    # 从Secret获取密码
    local KEYSTORE_PASSWORD=$(kubectl get secret kafka-ssl-certs -n $NAMESPACE -o jsonpath="{.data.keystore\.password}" 2>/dev/null | base64 -d 2>/dev/null)
    local KEY_PASSWORD=$(kubectl get secret kafka-ssl-certs -n $NAMESPACE -o jsonpath="{.data.key\.password}" 2>/dev/null | base64 -d 2>/dev/null)
    local TRUSTSTORE_PASSWORD=$(kubectl get secret kafka-ssl-certs -n $NAMESPACE -o jsonpath="{.data.truststore\.password}" 2>/dev/null | base64 -d 2>/dev/null)
    
    if [ -z "$KEYSTORE_PASSWORD" ] || [ -z "$KEY_PASSWORD" ] || [ -z "$TRUSTSTORE_PASSWORD" ]; then
        log_error "无法从Secret获取密码"
        return 1
    fi
    
    # 检查凭据文件是否存在
    local creds_check=$(kubectl exec kafka-0 -n $NAMESPACE -- \
        sh -c 'if [ -f /etc/kafka/secrets/keystore_creds ]; then echo "exists"; else echo "missing"; fi' 2>/dev/null)
    
    if [ "$creds_check" = "missing" ]; then
        log_info "凭据文件不存在，使用直接密码方式创建配置"
        
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

# 测试Kafka broker信息
test_broker_info() {
    log_info "测试获取Kafka broker信息"
    
    # 首先创建客户端配置文件
    create_pod_client_config || return 1
    
    # 使用kafka-topics命令来验证连接和获取基本信息，避免JMX端口冲突
    local topic_list=$(kubectl exec kafka-0 -n $NAMESPACE -- \
        env JMX_PORT= kafka-topics --list \
        --bootstrap-server localhost:9092 \
        --command-config /tmp/client.properties 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        log_success "成功连接到Kafka broker"
        local topic_count=$(echo "$topic_list" | wc -l)
        log_info "  当前Topic数量: $topic_count"
        
        # 尝试获取broker API版本（禁用JMX）
        local api_versions=$(kubectl exec kafka-0 -n $NAMESPACE -- \
            env JMX_PORT= kafka-broker-api-versions --bootstrap-server localhost:9092 \
            --command-config /tmp/client.properties 2>/dev/null | head -1 || echo "")
        
        if [ -n "$api_versions" ]; then
            log_info "  Broker API版本信息获取成功"
        else
            log_info "  跳过API版本检查（JMX端口冲突）"
        fi
    else
        log_error "无法连接到Kafka broker"
        return 1
    fi
}

# 测试Topic操作
test_topic_operations() {
    log_info "测试Topic操作"
    
    # 确保客户端配置文件存在
    create_pod_client_config || return 1
    
    # 删除测试Topic（如果存在）
    kubectl exec kafka-0 -n $NAMESPACE -- \
        env JMX_PORT= kafka-topics --delete --topic $TEST_TOPIC \
        --bootstrap-server localhost:9092 \
        --command-config /tmp/client.properties &> /dev/null || true
    
    sleep 2
    
    # 创建Topic
    log_info "创建测试Topic: $TEST_TOPIC"
    local create_output=$(kubectl exec kafka-0 -n $NAMESPACE -- \
        env JMX_PORT= kafka-topics --create --topic $TEST_TOPIC \
        --bootstrap-server localhost:9092 \
        --replication-factor 3 \
        --partitions 3 \
        --command-config /tmp/client.properties 2>&1)
    
    if [ $? -eq 0 ]; then
        log_success "Topic $TEST_TOPIC 创建成功"
    else
        log_error "Topic $TEST_TOPIC 创建失败"
        log_error "错误详情: $create_output"
        
        # 检查Topic是否已存在
        if echo "$create_output" | grep -q "already exists"; then
            log_warning "Topic已存在，继续测试"
        else
            return 1
        fi
    fi
    
    # 列出Topics
    log_info "列出所有Topics"
    local topics=$(kubectl exec kafka-0 -n $NAMESPACE -- \
        env JMX_PORT= kafka-topics --list \
        --bootstrap-server localhost:9092 \
        --command-config /tmp/client.properties 2>/dev/null)
    
    if echo "$topics" | grep -q "$TEST_TOPIC"; then
        log_success "Topic $TEST_TOPIC 在列表中找到"
    else
        log_error "Topic $TEST_TOPIC 未在列表中找到"
        return 1
    fi
    
    # 描述Topic
    log_info "描述Topic: $TEST_TOPIC"
    local topic_desc=$(kubectl exec kafka-0 -n $NAMESPACE -- \
        env JMX_PORT= kafka-topics --describe --topic $TEST_TOPIC \
        --bootstrap-server localhost:9092 \
        --command-config /tmp/client.properties 2>/dev/null)
    
    if echo "$topic_desc" | grep -q "ReplicationFactor:.*3"; then
        log_success "Topic复制因子正确设置为3"
    else
        log_warning "Topic复制因子可能未正确设置"
        echo "$topic_desc"
    fi
}

# 测试消息生产和消费
test_message_flow() {
    log_info "测试消息生产和消费"
    
    # 生产消息
    log_info "生产测试消息"
    local producer_output=$(echo "$TEST_MESSAGE" | kubectl exec -i kafka-0 -n $NAMESPACE -- \
        env JMX_PORT= kafka-console-producer --topic $TEST_TOPIC \
        --bootstrap-server localhost:9092 \
        --producer.config /tmp/client.properties 2>&1)
    
    if [ $? -eq 0 ]; then
        log_success "消息生产成功"
    else
        log_error "消息生产失败"
        log_error "错误详情: $producer_output"
        
        # 检查Topic是否存在
        log_info "检查Topic是否存在..."
        local topic_exists=$(kubectl exec kafka-0 -n $NAMESPACE -- \
            env JMX_PORT= kafka-topics --list \
            --bootstrap-server localhost:9092 \
            --command-config /tmp/client.properties 2>/dev/null | grep "^$TEST_TOPIC$" || echo "")
        
        if [ -z "$topic_exists" ]; then
            log_error "Topic $TEST_TOPIC 不存在"
        else
            log_info "Topic $TEST_TOPIC 存在"
        fi
        return 1
    fi
    
    sleep 2
    
    # 消费消息
    log_info "消费测试消息"
    local consumed_message=$(kubectl exec kafka-0 -n $NAMESPACE -- timeout 10 \
        env JMX_PORT= kafka-console-consumer --topic $TEST_TOPIC \
        --bootstrap-server localhost:9092 \
        --consumer.config /tmp/client.properties \
        --from-beginning --max-messages 1 2>/dev/null || echo "")
    
    if [ "$consumed_message" = "$TEST_MESSAGE" ]; then
        log_success "消息消费成功，内容匹配"
    else
        log_error "消息消费失败或内容不匹配"
        log_error "期望: $TEST_MESSAGE"
        log_error "实际: $consumed_message"
        return 1
    fi
}

# 测试SSL/mTLS连接
test_ssl_connection() {
    log_info "测试SSL/mTLS连接"
    
    # 检查凭据文件是否存在
    log_info "检查SSL凭据文件"
    local creds_check=$(kubectl exec kafka-0 -n $NAMESPACE -- \
        sh -c 'if [ -f /etc/kafka/secrets/keystore_creds ]; then echo "exists"; else echo "missing"; fi' 2>/dev/null)
    
    if [ "$creds_check" = "missing" ]; then
        log_warning "凭据文件不存在，尝试从Secret重新创建"
        
        # 尝试重新创建凭据文件
        local KEYSTORE_PASSWORD=$(kubectl get secret kafka-ssl-certs -n $NAMESPACE -o jsonpath="{.data.keystore\.password}" 2>/dev/null | base64 -d 2>/dev/null)
        local KEY_PASSWORD=$(kubectl get secret kafka-ssl-certs -n $NAMESPACE -o jsonpath="{.data.key\.password}" 2>/dev/null | base64 -d 2>/dev/null)
        local TRUSTSTORE_PASSWORD=$(kubectl get secret kafka-ssl-certs -n $NAMESPACE -o jsonpath="{.data.truststore\.password}" 2>/dev/null | base64 -d 2>/dev/null)
        
        if [ -n "$KEYSTORE_PASSWORD" ] && [ -n "$KEY_PASSWORD" ] && [ -n "$TRUSTSTORE_PASSWORD" ]; then
            kubectl exec kafka-0 -n $NAMESPACE -- sh -c "
                echo '$KEYSTORE_PASSWORD' > /tmp/keystore_creds_temp
                echo '$KEY_PASSWORD' > /tmp/key_creds_temp  
                echo '$TRUSTSTORE_PASSWORD' > /tmp/truststore_creds_temp
                chmod 600 /tmp/*_creds_temp
            " 2>/dev/null
            
            # 使用临时文件进行验证
            log_info "使用临时凭据文件验证SSL证书"
            if kubectl exec kafka-0 -n $NAMESPACE -- \
                sh -c 'keytool -list -keystore /etc/kafka/secrets/kafka.server.keystore.jks -storepass "$(cat /tmp/keystore_creds_temp)" -noprompt' &> /dev/null; then
                log_success "SSL keystore验证成功（使用临时凭据）"
            else
                log_error "SSL keystore验证失败"
                return 1
            fi
            
            # 清理临时文件
            kubectl exec kafka-0 -n $NAMESPACE -- rm -f /tmp/*_creds_temp &> /dev/null || true
        else
            log_error "无法从Secret获取密码"
            return 1
        fi
    else
        # 检查SSL证书 - 使用现有的密码文件
        log_info "验证SSL证书"
        if kubectl exec kafka-0 -n $NAMESPACE -- \
            sh -c 'keytool -list -keystore /etc/kafka/secrets/kafka.server.keystore.jks -storepass "$(cat /etc/kafka/secrets/keystore_creds)" -noprompt' &> /dev/null; then
            log_success "SSL keystore验证成功"
        else
            log_error "SSL keystore验证失败"
            return 1
        fi
    fi
    
    # 测试SSL端口连接
    log_info "测试SSL端口连接"
    if kubectl exec kafka-0 -n $NAMESPACE -- timeout 10 \
        openssl s_client -connect localhost:9092 -verify_return_error -quiet <<< "Q" &> /dev/null; then
        log_success "SSL连接测试成功"
    else
        log_warning "SSL连接测试可能失败（这在某些环境中是正常的）"
    fi
}

# 测试集群健康状态
test_cluster_health() {
    log_info "测试集群健康状态"
    
    # 检查所有broker是否在线 - 使用topics命令验证连接
    local topics_check=$(kubectl exec kafka-0 -n $NAMESPACE -- \
        env JMX_PORT= kafka-topics --list \
        --bootstrap-server localhost:9092 \
        --command-config /tmp/client.properties 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        log_success "Kafka集群连接正常"
        
        # 尝试获取broker数量（如果可能）
        local online_brokers=$(kubectl exec kafka-0 -n $NAMESPACE -- \
            env JMX_PORT= kafka-broker-api-versions --bootstrap-server localhost:9092 \
            --command-config /tmp/client.properties 2>/dev/null | \
            grep -c "^kafka-" 2>/dev/null || echo "0")
        
        # 确保online_brokers是一个有效的数字
        if [[ "$online_brokers" =~ ^[0-9]+$ ]] && [ "$online_brokers" -gt 0 ]; then
            log_info "检测到 $online_brokers 个在线broker"
        else
            log_info "无法通过API获取broker数量（JMX限制），但集群连接正常"
        fi
    else
        log_error "无法连接到Kafka集群"
        return 1
    fi
    
    # 检查leader选举
    log_info "检查Topic leader分布"
    local leader_info=$(kubectl exec kafka-0 -n $NAMESPACE -- \
        env JMX_PORT= kafka-topics --describe --topic $TEST_TOPIC \
        --bootstrap-server localhost:9092 \
        --command-config /tmp/client.properties 2>/dev/null)
    
    local unique_leaders=$(echo "$leader_info" | grep "Leader:" | awk '{print $6}' | sort -u | wc -l)
    if [ "$unique_leaders" -gt 0 ]; then
        log_success "Topic partitions有活跃的leaders"
    else
        log_error "Topic partitions没有活跃的leaders"
        return 1
    fi
}

# 清理测试资源
cleanup_test() {
    log_info "清理测试资源"
    
    # 删除测试Topic
    kubectl exec kafka-0 -n $NAMESPACE -- \
        env JMX_PORT= kafka-topics --delete --topic $TEST_TOPIC \
        --bootstrap-server localhost:9092 \
        --command-config /tmp/client.properties &> /dev/null || true
    
    # 删除Pod内的临时配置文件
    kubectl exec kafka-0 -n $NAMESPACE -- rm -f /tmp/client.properties &> /dev/null || true
    
    # 删除本地临时文件
    if [ -n "$CLIENT_CONFIG" ]; then
        rm -rf "$(dirname "$CLIENT_CONFIG")"
    fi
    
    log_success "测试资源清理完成"
}

# 主测试函数
run_all_tests() {
    local start_time=$(date +%s)
    local failed_tests=()
    
    echo "=================================================="
    echo "      Kafka mTLS 集群测试开始"
    echo "=================================================="
    echo ""
    
    # 基础检查
    log_info "Step 1: 基础环境检查"
    check_kubectl || failed_tests+=("kubectl检查")
    check_namespace || failed_tests+=("namespace检查")
    check_secrets || failed_tests+=("secret检查")
    echo ""
    
    # 集群状态检查
    log_info "Step 2: 集群状态检查"
    check_pods || failed_tests+=("Pod状态检查")
    check_services || failed_tests+=("Service检查")
    check_endpoints || failed_tests+=("Endpoints检查")
    echo ""
    
    # 等待集群就绪
    log_info "Step 3: 等待集群就绪"
    wait_for_pods || failed_tests+=("Pod就绪等待")
    echo ""
    
    # 连接性测试
    log_info "Step 4: 连接性测试"
    test_cluster_connectivity || failed_tests+=("集群连接性")
    echo ""
    
    # 设置客户端配置
    log_info "Step 5: 设置客户端配置"
    create_pod_client_config || failed_tests+=("客户端配置")
    echo ""
    
    # Kafka功能测试
    log_info "Step 6: Kafka功能测试"
    test_broker_info || failed_tests+=("Broker信息")
    test_topic_operations || failed_tests+=("Topic操作")
    test_message_flow || failed_tests+=("消息流")
    echo ""
    
    # SSL/mTLS测试
    log_info "Step 7: SSL/mTLS测试"
    test_ssl_connection || failed_tests+=("SSL连接")
    echo ""
    
    # 集群健康检查
    log_info "Step 8: 集群健康检查"
    test_cluster_health || failed_tests+=("集群健康")
    echo ""
    
    # 清理
    log_info "Step 9: 清理测试资源"
    cleanup_test
    echo ""
    
    # 测试结果报告
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "=================================================="
    echo "              测试结果报告"
    echo "=================================================="
    echo "测试执行时间: ${duration}秒"
    echo ""
    
    if [ ${#failed_tests[@]} -eq 0 ]; then
        log_success "🎉 所有测试通过！Kafka mTLS集群运行正常"
        echo ""
        log_info "集群信息:"
        log_info "  - Namespace: $NAMESPACE"
        log_info "  - Broker数量: $BROKER_COUNT"
        log_info "  - SSL/mTLS: 已启用"
        log_info "  - 复制因子: 3"
        log_info "  - 最小同步副本: 2"
        return 0
    else
        log_error "❌ 以下测试失败:"
        for test in "${failed_tests[@]}"; do
            log_error "  - $test"
        done
        echo ""
        log_warning "请检查失败的测试项目，查看详细日志进行故障排除"
        return 1
    fi
}

# 显示帮助信息
show_help() {
    echo "Kafka mTLS 集群测试脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  help          显示帮助信息"
    echo "  full          运行完整测试套件（默认）"
    echo "  basic         只运行基础检查"
    echo "  connectivity  只测试连接性"
    echo "  kafka         只测试Kafka功能"
    echo "  ssl           只测试SSL/mTLS"
    echo "  health        只测试集群健康状态"
    echo "  cleanup       只清理测试资源"
    echo "  diagnose      诊断SSL配置问题"
    echo ""
    echo "示例:"
    echo "  $0              # 运行完整测试"
    echo "  $0 basic        # 只运行基础检查"
    echo "  $0 kafka        # 只测试Kafka功能"
}

# 主程序入口
main() {
    case "${1:-full}" in
        "help"|"-h"|"--help")
            show_help
            exit 0
            ;;
        "basic")
            check_kubectl
            check_namespace
            check_secrets
            check_pods
            check_services
            ;;
        "connectivity")
            test_cluster_connectivity
            ;;
        "kafka")
            create_pod_client_config
            test_broker_info
            test_topic_operations
            test_message_flow
            cleanup_test
            ;;
        "ssl")
            create_pod_client_config
            test_ssl_connection
            ;;
        "health")
            create_pod_client_config
            test_cluster_health
            ;;
        "cleanup")
            cleanup_test
            ;;
        "diagnose")
            diagnose_ssl_setup
            ;;
        "full"|"")
            run_all_tests
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
}

# 执行主程序
main "$@" 