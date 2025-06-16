# Loki Demo环境项目结构

## 📁 文件列表

```
grafana-stack/
├── 🔧 核心配置文件
│   ├── loki-configmap-demo.yaml        # Demo环境Loki配置
│   ├── loki-deployment-demo.yaml       # Demo环境部署配置
│   └── loki-serviceaccount.yaml        # Workload Identity服务账号
│
├── 🚀 部署脚本
│   ├── deploy-loki-demo.sh             # Demo环境自动部署脚本
│   └── setup-workload-identity.sh      # Workload Identity设置脚本
│
└── 📚 文档
    ├── README.md                        # 项目使用说明
    └── PROJECT-STRUCTURE.md            # 本文件
```

## 🎯 Demo环境特点

### 📊 简化配置
- **单副本部署** - 资源占用最小
- **无认证模式** - 简化访问和测试
- **emptyDir存储** - 无需持久化卷
- **基础资源配置** - 500m CPU, 1GB内存

### 🔧 技术栈
- **Loki版本**: 3.1.1
- **存储**: GCS + emptyDir
- **Schema**: v13 + TSDB
- **命名空间**: grafana-stack

## 🚀 快速开始

```bash
# 一键部署
./deploy-loki-demo.sh

# 验证部署
kubectl get pods -l app=loki -n grafana-stack

# 测试访问
kubectl port-forward svc/loki 3100:3100 -n grafana-stack
curl http://localhost:3100/ready
```

## 📊 资源使用

| 组件 | CPU请求 | CPU限制 | 内存请求 | 内存限制 |
|------|---------|---------|----------|----------|
| Loki | 500m    | 1000m   | 1Gi      | 2Gi      |

## ⚠️ 注意事项

- **非生产环境** - 仅用于Demo和测试
- **数据非持久化** - Pod重启会丢失本地数据
- **无高可用** - 单副本无故障转移
- **无监控告警** - 未包含监控配置

---

**总文件**: 7个  
**环境类型**: Demo/测试  
**部署时间**: ~2分钟 