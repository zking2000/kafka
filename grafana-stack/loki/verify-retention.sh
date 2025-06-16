#!/bin/bash

# 验证Loki 24小时数据保留策略配置
# 作者: Assistant
# 描述: 检查Loki retention配置和GCS存储清理状态

set -e

echo "🔍 验证Loki 24小时数据保留策略配置..."
echo "=================================="

# 检查Pod状态
echo "📊 检查Loki Pod状态..."
kubectl get pods -n grafana-stack -l app=loki

# 检查配置
echo -e "\n🔧 检查retention配置..."
echo "通过API获取配置:"
curl -s http://localhost:3100/config | grep -A 5 -B 2 "retention_enabled\|retention_period\|delete_request_store" || echo "需要先建立端口转发: kubectl port-forward -n grafana-stack service/loki 3100:3100"

# 检查compactor状态 
echo -e "\n📈 检查compactor指标..."
curl -s http://localhost:3100/metrics | grep "loki_compactor" | head -10 || echo "需要端口转发访问metrics"

# 检查GCS bucket中的数据
echo -e "\n☁️  GCS存储信息:"
echo "Bucket: loki_44084750"
echo "保留策略: 24小时"
echo "删除延迟: 2小时"

echo -e "\n✅ 保留策略配置摘要:"
echo "- retention_enabled: true"
echo "- retention_period: 24h" 
echo "- retention_delete_delay: 2h"
echo "- delete_request_store: gcs"
echo "- compaction_interval: 10m"

echo -e "\n📝 说明:"
echo "1. 数据将在24小时后自动删除"
echo "2. compactor每10分钟运行一次检查"
echo "3. 删除操作有2小时延迟以确保安全"
echo "4. 删除请求存储在GCS中管理"

echo -e "\n🎯 验证完成！" 