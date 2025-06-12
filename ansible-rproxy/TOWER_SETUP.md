# Ansible Tower 配置指南

## 📋 概述

本指南描述如何在Ansible Tower中配置Apache反向代理备份任务。已针对Tower环境进行了优化，包括凭据管理、任务模板和工作流配置。

## 🔧 Tower配置步骤

### 1. 创建凭据 (Credentials)

#### SSH凭据
```yaml
名称: GCP-SSH-Key
类型: Machine
用户名: stephen_h_zhou  # 或您的OS Login用户名
SSH私钥: # 粘贴 ~/.ssh/google_compute_engine 内容
特权升级方法: sudo
```

#### GitHub凭据
```yaml
名称: GitHub-Token
类型: Source Control
用户名: your-github-username
密码: ghp_your_github_personal_access_token_here
```

### 2. 创建项目 (Project)

```yaml
名称: Apache-Backup-Project
SCM类型: Git
SCM URL: https://github.com/your-username/ansible-rproxy.git
凭据: GitHub-Token
SCM分支: main
SCM更新选项:
  - 启动时清理
  - 启动时更新修订版本
  - 启动时删除
```

### 3. 创建清单 (Inventory)

#### 清单配置
```yaml
名称: Apache-Servers
```

#### 主机配置
```yaml
主机名: dev-rproxy-1
变量:
  ansible_host: 34.142.72.180  # 从Terraform输出获取
  ansible_port: 2234
  github_branch: dev-rproxy-1
```

#### 组变量 (rproxy组)
```yaml
ansible_python_interpreter: /usr/bin/python3
backup_dir: /tmp/apache_backup
ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
ansible_ssh_pipelining: yes
ansible_ssh_timeout: 30
```

### 4. 创建任务模板 (Job Templates)

#### 备份任务模板
```yaml
名称: Apache配置备份
作业类型: 运行
清单: Apache-Servers
项目: Apache-Backup-Project
Playbook: playbooks/apache-backup-tower.yml
凭据:
  - GCP-SSH-Key (Machine)

变量:
  github_repo: "your-username/apache-config-backup"
  github_token: "{{ github_token }}"  # 从凭据中获取
  git_user_name: "Your Name"
  git_user_email: "your.email@example.com"

选项:
  ✅ 启用特权升级
  ✅ 启用详细输出
  ✅ 启用主机密钥检查
  ✅ 启用事实缓存
```

#### Git推送任务模板
```yaml
名称: 推送备份到GitHub
作业类型: 运行
清单: Apache-Servers
项目: Apache-Backup-Project
Playbook: playbooks/git-push-tower.yml
凭据:
  - GitHub-Token (Source Control)

变量:
  github_repo: "your-username/apache-config-backup"
  github_token: "{{ github_token }}"
  git_user_name: "Your Name"
  git_user_email: "your.email@example.com"
  tower_project_path: "/tmp/tower-projects"
```

### 5. 创建工作流模板 (Workflow Template)

```yaml
名称: 完整Apache备份流程
工作流节点:
  1. Apache配置备份
     ↓ (成功时)
  2. 推送备份到GitHub
```

## 🎯 Survey配置 (可选)

为任务模板添加Survey，让用户可以动态配置参数：

### 备份任务Survey
```yaml
1. 目标主机选择:
   变量名: limit
   类型: Multiple Choice
   选项: dev-rproxy-1, prod-rproxy-1, staging-rproxy-1

2. GitHub分支:
   变量名: github_branch
   类型: Text
   默认值: main

3. 备份目录:
   变量名: backup_dir
   类型: Text
   默认值: /tmp/apache_backup
```

## 🔄 Terraform集成

使用提供的脚本自动更新Tower inventory：

```bash
# 在terraform目录中执行
./update-inventory.sh
```

或者手动从Terraform输出更新：

```bash
# 获取主机信息
terraform output ansible_inventory

# 在Tower中更新对应主机的变量
```

## 📊 监控和日志

### 查看任务执行状态
1. 转到 Jobs 页面
2. 查看任务执行历史
3. 点击任务查看详细日志

### 设置通知
```yaml
通知类型: Email/Slack
名称: Apache备份通知
消息模板: |
  Apache配置备份任务已完成
  状态: {{ job_status }}
  主机: {{ job_hosts }}
  开始时间: {{ job_start }}
  结束时间: {{ job_end }}
```

## 🔐 安全最佳实践

### 凭据安全
- ✅ 使用Tower凭据存储，不在playbook中硬编码
- ✅ 定期轮换GitHub token
- ✅ 使用最小权限原则

### 访问控制
```yaml
团队: DevOps-Team
角色: Execute
资源: Apache备份相关模板
```

### 审计日志
- ✅ 启用Tower活动流
- ✅ 配置外部日志记录
- ✅ 定期审查访问日志

## 🚀 快速开始

### 最小化配置
1. 创建SSH凭据和GitHub凭据
2. 导入项目
3. 创建清单和主机
4. 运行备份任务模板

### 验证配置
```bash
# 在Tower中运行
ansible-playbook playbooks/apache-backup-tower.yml -i inventory/tower-hosts.yml --limit dev-rproxy-1 --check
```

## 🛠️ 故障排除

### 常见问题

1. **SSH连接失败**
   ```
   检查项:
   - OS Login权限
   - SSH端口(2234)
   - 防火墙规则
   - 凭据配置
   ```

2. **Git推送失败**
   ```
   检查项:
   - GitHub token权限
   - 仓库访问权限
   - 网络连接
   ```

3. **文件权限问题**
   ```
   解决方案:
   - 确保become: yes
   - 检查目录权限
   - 验证用户权限
   ```

### 调试命令
```bash
# 在Tower执行节点上
ls -la /tmp/extracted/
cat /var/log/tower/job_events/*.log
```

## 📝 维护

### 定期任务
- 清理临时文件: 每周
- 更新凭据: 每月
- 审查权限: 每季度
- 备份Tower配置: 每月

### 监控指标
- 任务成功率
- 执行时间
- 存储使用量
- 网络传输量 