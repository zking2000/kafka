#!/bin/bash

# ========= 配置部分：请修改下面这几个变量 =========
KAFKA_HOSTS=(
    "kafka-0.kafka.internal.cloud"
    "kafka-1.kafka.internal.cloud"
    "kafka-2.kafka.internal.cloud"
)
PORTS=("9093")  # Kafka 的 mTLS 端口列表

# 确保脚本在正确的目录下执行
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR" || exit 1

# 以下是本地用于 mTLS 的证书路径
CLIENT_CERT="client-cert.crt"         # mTLS 客户端证书
CLIENT_KEY="client-key.key"          # mTLS 客户端私钥
CA_CERT="ca-cert.crt"                 # Kafka 信任的 CA 根证书

# 检查证书文件是否存在
for cert in "$CLIENT_CERT" "$CLIENT_KEY" "$CA_CERT"; do
    if [[ ! -f "$cert" ]]; then
        echo "错误: 找不到证书文件 $cert"
        exit 1
    fi
done

# ========= 测试逻辑 =========
for HOST in "${KAFKA_HOSTS[@]}"; do
    echo "📍 测试 Kafka 节点: $HOST"
    echo "=============================================="
    
    for PORT in "${PORTS[@]}"; do
        echo "🔍 正在测试 $HOST:$PORT ..."
        
        # 先测试端口是否开放
        if ! nc -z -w5 "$HOST" "$PORT"; then
            echo "❌ [$HOST:$PORT] 端口未开放或无法访问"
            echo "------------------------------------------------------"
            continue
        fi
        
        # 保存完整的 SSL 调试信息
        openssl s_client \
            -connect "$HOST:$PORT" \
            -cert "$CLIENT_CERT" \
            -key "$CLIENT_KEY" \
            -CAfile "$CA_CERT" \
            -servername "$HOST" \
            -showcerts \
            -state \
            -debug \
            -verify_return_error \
            < /dev/null > "result_${HOST}_${PORT}.txt" 2>&1

        # 分析结果
        {
            echo "测试结果分析:"
            echo "------------"
            # 检查证书验证
            if grep -q "Verify return code: 0 (ok)" "result_${HOST}_${PORT}.txt"; then
                echo "✅ 证书验证成功"
            else
                echo "❌ 证书验证失败"
                grep "verify" "result_${HOST}_${PORT}.txt" | tail -n 2
            fi
            
            # 检查是否收到服务器证书
            if grep -q "Server certificate" "result_${HOST}_${PORT}.txt"; then
                echo "✅ 收到服务器证书"
            else
                echo "❌ 未收到服务器证书"
            fi
            
            # 检查是否完成 SSL 握手
            if grep -q "SSL handshake has read" "result_${HOST}_${PORT}.txt"; then
                HANDSHAKE=$(grep "SSL handshake has read" "result_${HOST}_${PORT}.txt")
                if [[ $HANDSHAKE =~ "read 0 bytes" ]]; then
                    echo "❌ SSL握手未完成"
                else
                    echo "✅ SSL握手完成"
                fi
            fi
            
            # 检查加密套件
            if grep -q "New, " "result_${HOST}_${PORT}.txt"; then
                CIPHER=$(grep "New, " "result_${HOST}_${PORT}.txt" | cut -d',' -f3-)
                if [[ $CIPHER == *"(NONE)"* ]]; then
                    echo "❌ 未协商加密套件"
                else
                    echo "✅ 使用加密套件: $CIPHER"
                fi
            fi
        } | tee -a "result_${HOST}_${PORT}.txt"

        echo "详细日志已保存到 result_${HOST}_${PORT}.txt"
        echo "------------------------------------------------------"
    done
done
