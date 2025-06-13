# Apache配置备份工具 - Ansible Tower版

这是专门为Ansible Tower/AWX环境优化的Apache配置备份工具，支持通过代理服务器连接到Apache反向代理服务器，自动备份配置文件并推送到Git仓库。

## 🌟 Tower版本特性

- 🏗️ **Tower原生支持** - 完全适配Tower/AWX的工作流程
- 🔐 **凭据管理** - 使用Tower的Credential系统安全管理敏感信息
- 📊 **可视化监控** - 通过Tower界面监控作业执行状态
- 🔔 **通知集成** - 支持Email、Slack等多种通知方式
- 📋 **Survey支持** - 运行时动态配置参数
- ⏰ **定时调度** - 支持cron风格的定时执行
- 🔗 **代理连接** - 支持多种代理连接方式
- 🚀 **本地Git操作** - 所有Git操作在Tower执行节点进行

## 📁 项目结构

```
ansible-rproxy-tower/
├── README.md                      # 本文档
├── TOWER_SETUP.md                # Tower配置详细指南
├── ansible.cfg                    # Tower优化的Ansible配置
├── requirements.txt               # Tower环境依赖
├── inventory/
│   └── tower-hosts.yml           # Tower inventory模板
└── playbooks/
    └── apache-backup-tower.yml   # Tower优化的playbook
```

## 🚀 快速开始

### 1. 导入项目到Tower

1. 在Tower中创建新项目
2. 配置Git仓库URL
3. 选择 `ansible-rproxy-tower` 目录作为项目根目录

### 2. 配置凭据

创建以下凭据：
- **SSH凭据**: 用于连接目标服务器
- **GitHub凭据**: 用于Git操作

### 3. 创建清单

- 添加目标服务器到清单
- 配置主机变量和组变量

### 4. 创建作业模板

- 选择playbook: `playbooks/apache-backup-tower.yml`
- 配置Extra Variables
- 添加必要的凭据

### 5. 运行作业

点击🚀按钮启动备份任务

## 🔧 配置说明

### 必需的Extra Variables

```yaml
# Git配置
tower_github_repo: "your-username/your-repo"
tower_github_token: "{{ github_token }}"
tower_git_user_name: "Your Name"
tower_git_user_email: "your.email@example.com"

# 代理配置
tower_proxy_host: "proxy.example.com"
tower_proxy_port: 22
tower_proxy_user: "stephen_h_zhou"

# 目标服务器配置
tower_target_host: "10.0.1.100"
tower_ssh_user: "stephen_h_zhou"
```

### 可选配置

```yaml
tower_github_branch: "main"
tower_backup_dir: "/tmp/apache_backup"
tower_cleanup_temp_files: false
tower_send_notifications: true
```

## 🔗 代理连接支持

支持以下代理连接方式：

### SSH ProxyJump（推荐）
```yaml
tower_proxy_host: "bastion.example.com"
tower_proxy_port: 22
tower_proxy_user: "stephen_h_zhou"
```

### 自定义SSH参数
```yaml
ansible_ssh_common_args: >-
  -o ProxyJump=user@proxy:port
  -o StrictHostKeyChecking=no
```

## 📋 工作流程

1. **Tower调度** - 根据配置的计划或手动触发
2. **代理连接** - 通过代理服务器连接到目标服务器
3. **远程备份** - 在目标服务器创建Apache配置zip包
4. **文件下载** - 下载到Tower执行节点
5. **Git操作** - 在Tower执行节点进行Git克隆、提交、推送
6. **通知发送** - 发送执行结果通知

## 📊 监控和日志

### Tower界面监控
- 实时查看作业执行状态
- 查看详细的执行日志
- 监控资源使用情况

### 通知配置
- Email通知作业结果
- Slack集成
- Webhook通知

## 🔒 安全特性

### 凭据安全
- 敏感信息通过Tower Credentials管理
- 支持凭据轮换
- 审计日志记录

### 权限控制
- RBAC权限管理
- 组织级别隔离
- 作业执行权限控制

## 🛠️ 故障排除

### 常见问题

1. **SSH连接失败**
   - 检查SSH凭据配置
   - 验证代理服务器连接
   - 确认网络连通性

2. **Git推送失败**
   - 验证GitHub令牌权限
   - 检查仓库访问权限
   - 确认分支存在

3. **Tower执行问题**
   - 检查执行节点资源
   - 验证依赖包安装
   - 查看Tower日志

### 调试技巧

- 启用详细日志输出
- 使用Tower的调试功能
- 检查执行节点状态

## 📈 性能优化

### Tower配置
- 合理配置并发数
- 优化SSH连接参数
- 调整超时设置

### 网络优化
- 使用SSH连接复用
- 优化代理连接配置
- 配置合适的缓存策略

## 🔄 维护和升级

### 定期维护
- 更新依赖包
- 清理临时文件
- 备份Tower配置

### 版本管理
- 使用Git管理代码变更
- 建立变更审批流程
- 定期更新文档

## 📚 相关文档

- [TOWER_SETUP.md](TOWER_SETUP.md) - 详细的Tower配置指南
- [Ansible Tower官方文档](https://docs.ansible.com/ansible-tower/)
- [AWX项目](https://github.com/ansible/awx)

## 🤝 支持

如有问题或建议，请：
1. 查看故障排除部分
2. 检查Tower日志
3. 联系系统管理员

---

**注意**: 这是Tower专用版本，如需本地执行版本，请使用主目录中的文件。 