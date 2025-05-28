# Kafka mTLS 故障排除指南

## 常见问题和解决方案

### 1. 证书相关问题

#### 证书未就绪
```bash
# 检查证书状态
kubectl get certificates -n kafka
kubectl describe certificate kafka-server-cert -n kafka

# 如果证书卡在Pending状态，检查cert-manager日志
kubectl logs -n cert-manager deployment/cert-manager
```

#### 证书验证失败
```bash
# 检查证书内容
kubectl get secret kafka-server-tls -n kafka -o yaml
kubectl get secret kafka-client-tls -n kafka -o yaml

# 验证证书有效性
kubectl exec -it kafka-client -n kafka -- openssl x509 -in /etc/certs/tls.crt -text -noout
```

### 2. Zookeeper连接问题

#### Zookeeper启动失败
```bash
# 检查Zookeeper日志
kubectl logs zookeeper-0 -n kafka

# 检查配置
kubectl describe configmap zookeeper-config -n kafka

# 检查存储
kubectl get pvc -n kafka
```

#### SSL连接错误
```bash
# 检查SSL配置
kubectl exec -it zookeeper-0 -n kafka -- netstat -tulpn | grep 2182

# 测试SSL连接
kubectl exec -it kafka-client -n kafka -- \
  openssl s_client -connect zookeeper-service:2182 -cert /etc/certs/tls.crt -key /etc/certs/tls.key
```

### 3. Kafka连接问题

#### Broker启动失败
```bash
# 检查Kafka日志
kubectl logs kafka-0 -n kafka

# 检查JVM参数
kubectl describe pod kafka-0 -n kafka

# 检查磁盘空间
kubectl exec -it kafka-0 -n kafka -- df -h
```

#### mTLS握手失败
```bash
# 检查SSL配置
kubectl exec -it kafka-0 -n kafka -- cat /etc/kafka/server.properties | grep ssl

# 测试SSL连接
kubectl exec -it kafka-client -n kafka -- \
  openssl s_client -connect kafka-service:9093 -cert /etc/certs/tls.crt -key /etc/certs/tls.key
```

### 4. 客户端连接问题

#### 客户端认证失败
```bash
# 检查客户端配置
kubectl exec -it kafka-client -n kafka -- cat /etc/kafka/client.properties

# 检查客户端证书
kubectl exec -it kafka-client -n kafka -- \
  keytool -list -keystore /etc/kafka/secrets/kafka-client-tls/keystore.jks -storepass changeit

# 检查truststore
kubectl exec -it kafka-client -n kafka -- \
  keytool -list -keystore /etc/kafka/secrets/kafka-client-tls/truststore.jks -storepass changeit
```

#### 连接超时
```bash
# 检查网络连通性
kubectl exec -it kafka-client -n kafka -- nc -zv kafka-service 9093

# 检查DNS解析
kubectl exec -it kafka-client -n kafka -- nslookup kafka-service

# 检查防火墙规则（GKE网络策略）
kubectl get networkpolicies -n kafka
```

### 5. 性能问题

#### 内存不足
```bash
# 检查资源使用
kubectl top pods -n kafka

# 调整资源限制
kubectl patch statefulset kafka -n kafka -p '{"spec":{"template":{"spec":{"containers":[{"name":"kafka","resources":{"limits":{"memory":"4Gi"}}}]}}}}'
```

#### 磁盘空间不足
```bash
# 检查磁盘使用
kubectl exec -it kafka-0 -n kafka -- du -sh /var/lib/kafka/logs/*

# 清理旧日志
kubectl exec -it kafka-0 -n kafka -- find /var/lib/kafka/logs -name "*.log" -mtime +7 -delete
```

### 6. 证书轮换

#### 手动轮换证书
```bash
# 删除现有证书以触发重新生成
kubectl delete certificate kafka-server-cert -n kafka
kubectl apply -f certificates.yaml

# 重启pod以加载新证书
kubectl rollout restart statefulset kafka -n kafka
kubectl rollout restart statefulset zookeeper -n kafka
```

### 7. 监控和日志

#### 启用调试日志
```bash
# 修改日志级别
kubectl patch configmap kafka-config -n kafka --patch '{"data":{"log4j.properties":"log4j.rootLogger=DEBUG, stdout\nlog4j.appender.stdout=org.apache.log4j.ConsoleAppender\nlog4j.appender.stdout.layout=org.apache.log4j.PatternLayout\nlog4j.appender.stdout.layout.ConversionPattern=[%d] %p %m (%c)%n"}}'

# 重启以应用新配置
kubectl rollout restart statefulset kafka -n kafka
```

#### 查看JMX指标
```bash
# 连接JMX端口
kubectl port-forward kafka-0 9999:9999 -n kafka

# 使用JConsole或其他JMX客户端连接 localhost:9999
```

### 8. 备份和恢复

#### 备份Kafka数据
```bash
# 创建topic数据快照
kubectl exec -it kafka-client -n kafka -- \
  kafka-topics --bootstrap-server kafka-service:9093 \
  --describe --command-config /etc/kafka/client.properties > topics-backup.txt
```

#### 备份证书
```bash
# 导出证书
kubectl get secret kafka-server-tls -n kafka -o yaml > kafka-server-tls-backup.yaml
kubectl get secret kafka-client-tls -n kafka -o yaml > kafka-client-tls-backup.yaml
kubectl get secret zookeeper-server-tls -n kafka -o yaml > zookeeper-server-tls-backup.yaml
```

### 9. 清理和重新部署

#### 完全清理
```bash
# 删除所有资源
kubectl delete namespace kafka

# 清理PVC（如果需要）
kubectl delete pvc -l app=kafka
kubectl delete pvc -l app=zookeeper

# 重新部署
./scripts/deploy.sh
```

### 10. 常用调试命令

```bash
# 查看所有资源状态
kubectl get all -n kafka

# 查看事件
kubectl get events -n kafka --sort-by=.metadata.creationTimestamp

# 查看配置
kubectl get configmaps -n kafka
kubectl get secrets -n kafka

# 实时查看日志
kubectl logs -f kafka-0 -n kafka
kubectl logs -f zookeeper-0 -n kafka

# 进入容器调试
kubectl exec -it kafka-0 -n kafka -- bash
kubectl exec -it kafka-client -n kafka -- bash
``` 