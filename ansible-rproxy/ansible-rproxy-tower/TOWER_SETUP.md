# Ansible Tower配置指南

这是Apache配置备份工具的Ansible Tower版本，专门为Tower/AWX环境优化。

## 🏗️ Tower项目结构

```
ansible-rproxy-tower/
├── ansible.cfg                    # Tower优化的Ansible配置
├── requirements.txt               # Tower环境依赖
├── TOWER_SETUP.md                # 本文档
├── inventory/
│   └── tower-hosts.yml           # Tower inventory模板
└── playbooks/
    └── apache-backup-tower.yml   # Tower优化的playbook
```

## 🚀 Tower配置步骤

### 1. 创建项目 (Project)

在Tower中创建新项目：

- **Name**: `Apache RProxy Backup`
- **Organization**: 选择您的组织
- **SCM Type**: `Git`
- **SCM URL**: 您的Git仓库URL
- **SCM Branch/Tag/Commit**: `main`
- **SCM Update Options**: 
  - ✅ Clean
  - ✅ Delete on Update
  - ✅ Update Revision on Launch

### 2. 创建凭据 (Credentials)

#### SSH凭据 (Machine Credential)
- **Name**: `RProxy SSH Key`
- **Type**: `Machine`
- **Username**: `stephen_h_zhou`
- **SSH Private Key**: 粘贴您的SSH私钥内容

#### GitHub凭据 (Source Control Credential)
- **Name**: `GitHub Token`
- **Type**: `Source Control`
- **Username**: 您的GitHub用户名
- **Password**: 您的GitHub Personal Access Token

### 3. 创建清单 (Inventory)

- **Name**: `RProxy Servers`
- **Organization**: 选择您的组织

#### 添加主机 (Hosts)
在清单中添加主机，例如：
- **Name**: `prod-rproxy-1`
- **Variables** (YAML格式):
```yaml
ansible_host: "10.0.1.100"
ansible_user: "stephen_h_zhou"
ansible_port: 22
github_branch: "main"
```

#### 添加组 (Groups)
- **Name**: `rproxy`
- 将主机添加到此组

### 4. 创建作业模板 (Job Template)

- **Name**: `Apache Backup Job`
- **Job Type**: `Run`
- **Inventory**: `RProxy Servers`
- **Project**: `Apache RProxy Backup`
- **Playbook**: `playbooks/apache-backup-tower.yml`
- **Credentials**: 
  - `RProxy SSH Key` (Machine)
  - `GitHub Token` (Source Control)
- **Verbosity**: `1 (Verbose)`

#### Extra Variables (额外变量)
在Job Template的Extra Variables中配置：

```yaml
# 必需变量
tower_github_repo: "your-username/your-repo"
tower_github_token: "{{ github_token }}"  # 从凭据中获取
tower_git_user_name: "Your Name"
tower_git_user_email: "your.email@example.com"
tower_github_branch: "main"

# 代理配置
tower_proxy_host: "proxy.example.com"
tower_proxy_port: 22
tower_proxy_user: "stephen_h_zhou"

# 目标服务器配置
tower_target_host: "10.0.1.100"
tower_ssh_user: "stephen_h_zhou"
tower_ssh_port: 22

# 可选配置
tower_backup_dir: "/tmp/apache_backup"
tower_cleanup_temp_files: false
tower_send_notifications: true
```

### 5. 创建调查 (Survey) - 可选

为了让用户在运行时选择参数，可以创建Survey：

#### 问题示例：
1. **目标服务器IP**
   - Variable: `tower_target_host`
   - Type: `Text`
   - Required: ✅

2. **Git分支**
   - Variable: `tower_github_branch`
   - Type: `Multiple Choice`
   - Choices: `main`, `dev`, `staging`
   - Default: `main`

3. **清理临时文件**
   - Variable: `tower_cleanup_temp_files`
   - Type: `Multiple Choice`
   - Choices: `true`, `false`
   - Default: `false`

## 🔧 代理连接配置

### 在Tower中配置代理连接

#### 方法1: 通过Extra Variables
```yaml
tower_proxy_host: "bastion.example.com"
tower_proxy_port: 22
tower_proxy_user: "stephen_h_zhou"
```

#### 方法2: 通过Host Variables
在Inventory的Host Variables中：
```yaml
ansible_ssh_common_args: >-
  -o ProxyJump=stephen_h_zhou@bastion.example.com:22
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
```

## 📋 运行作业

### 手动运行
1. 进入 **Templates** 页面
2. 点击 `Apache Backup Job` 旁的火箭图标 🚀
3. 如果配置了Survey，填写相关参数
4. 点击 **Launch** 开始执行

### 定时运行
1. 在Job Template页面点击 **Schedules**
2. 点击 **+** 添加新计划
3. 配置运行时间（例如：每天凌晨2点）
4. 保存计划

## 📊 监控和日志

### 查看作业状态
- **Jobs** 页面显示所有作业的执行状态
- 点击作业ID查看详细日志
- 使用过滤器查找特定作业

### 通知配置
在 **Notification Templates** 中配置：
- Email通知
- Slack通知
- Webhook通知

## 🔒 安全最佳实践

### 凭据管理
- ✅ 使用Tower的Credential系统存储敏感信息
- ✅ 定期轮换SSH密钥和API令牌
- ✅ 限制凭据的使用范围

### 权限控制
- ✅ 使用RBAC控制用户权限
- ✅ 为不同环境创建不同的组织
- ✅ 限制生产环境的访问权限

### 审计日志
- ✅ 启用Tower的审计日志
- ✅ 定期检查作业执行记录
- ✅ 监控异常活动

## 🛠️ 故障排除

### 常见问题

#### 1. SSH连接失败
- 检查SSH凭据配置
- 验证代理服务器连接
- 确认防火墙规则

#### 2. Git推送失败
- 验证GitHub令牌权限
- 检查仓库是否存在
- 确认分支名称正确

#### 3. Tower执行节点问题
- 检查执行节点的磁盘空间
- 验证Python依赖安装
- 查看Tower服务日志

### 调试技巧
- 使用 `--verbose` 选项增加日志详细程度
- 在playbook中添加 `debug` 任务输出变量值
- 检查Tower的 `/var/log/tower/` 日志文件

## 📈 性能优化

### Tower配置优化
- 调整 `forks` 参数控制并发数
- 使用 `pipelining` 减少SSH连接
- 配置适当的超时时间

### 网络优化
- 使用SSH连接复用
- 配置合适的代理连接参数
- 优化防火墙规则

## 🔄 升级和维护

### 定期维护任务
- 更新Ansible和依赖包
- 清理Tower执行节点的临时文件
- 备份Tower配置和数据库
- 检查和更新SSL证书

### 版本控制
- 将Tower配置导出为代码
- 使用Git管理playbook变更
- 建立变更审批流程 