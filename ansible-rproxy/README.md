# Apache反向代理配置备份 Ansible Playbook

这套完整的解决方案包含：

**🏗️ Terraform基础设施部署**：
- 在GCP上自动创建Apache反向代理VM
- 配置网络、防火墙和安全设置
- 自动安装和配置Apache反向代理

**🔧 Ansible配置管理**：
1. 远程登录到Apache反向代理虚拟机
2. 将`/etc/httpd/conf`目录打包成ZIP文件
3. 将ZIP文件下载到本地
4. 解压文件并推送到GitHub仓库的对应分支

## 📁 项目结构

```
ansible-rproxy/
├── ansible.cfg              # Ansible配置文件
├── inventory/
│   └── hosts.yml           # 主机清单文件
├── playbooks/
│   └── apache-backup.yml   # 主要的playbook文件
├── group_vars/
│   └── all.yml             # 全局变量配置
├── terraform/              # Terraform基础设施代码
│   ├── main.tf             # 主配置文件
│   ├── variables.tf        # 变量定义
│   ├── outputs.tf          # 输出定义
│   ├── terraform.tfvars.example # 变量值示例
│   ├── deploy.sh           # 部署脚本
│   ├── scripts/
│   │   └── startup.sh      # VM启动脚本
│   └── README.md           # Terraform文档
├── run-backup.sh           # Ansible执行脚本
├── update-inventory.sh     # 从Terraform更新inventory
├── test-connection.sh      # 连接测试脚本
└── README.md              # 本文档
```

## 🚀 快速开始

### 选项1: 使用Terraform自动创建VM（推荐）

如果您想在GCP上自动创建和配置Apache反向代理VM，请先使用Terraform：

```bash
# 1. 进入terraform目录
cd terraform

# 2. 配置terraform.tfvars
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # 修改项目ID等配置

# 3. 部署基础设施
./deploy.sh apply dev

# 4. 更新Ansible inventory
cd ..
./update-inventory.sh

# 5. 运行配置备份
./run-backup.sh
```

详细的Terraform使用说明请参见：[terraform/README.md](terraform/README.md)

### 选项2: 使用现有VM

如果您已有Apache反向代理VM，可以直接使用Ansible部分：

### 1. 环境准备

确保您的系统已安装：
- Ansible (≥ 2.9)
- Git
- Python 3
- SSH客户端

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install ansible git python3

# CentOS/RHEL
sudo yum install ansible git python3

# macOS
brew install ansible git
```

### 2. 配置文件修改

#### 2.1 修改主机清单 (`inventory/hosts.yml`)

根据您的实际环境修改主机信息：

```yaml
all:
  children:
    rproxy:
      hosts:
        dev-hk:
          ansible_host: 192.168.1.10    # 修改为实际IP
          ansible_user: root             # 修改为实际用户
          github_branch: dev-hk          # 对应的GitHub分支
        prod-us:
          ansible_host: 192.168.1.20
          ansible_user: root
          github_branch: prod-us
```

#### 2.2 配置GitHub信息 (`group_vars/all.yml`)

修改GitHub仓库信息：

```yaml
github_repo: "your-username/apache-config-backup"  # 修改为您的仓库
```

#### 2.3 设置GitHub访问令牌

直接在`group_vars/all.yml`文件中修改GitHub token：

```yaml
github_token: "ghp_your_actual_github_token_here"
```

**⚠️ 重要提醒**: GitHub token是敏感信息，请确保不要将包含真实token的文件提交到公开的代码仓库中。

### 3. SSH密钥配置

确保您的SSH密钥已配置到目标主机：

```bash
# 生成SSH密钥（如果还没有）
ssh-keygen -t rsa -b 4096

# 复制公钥到目标主机
ssh-copy-id root@192.168.1.10
```

### 4. 运行备份

#### 4.1 使用执行脚本（推荐）

```bash
# 备份所有rproxy主机
./run-backup.sh

# 备份特定主机
./run-backup.sh dev-hk
```

#### 4.2 直接使用ansible-playbook

```bash
# 备份所有主机
ansible-playbook playbooks/apache-backup.yml

# 备份特定主机
ansible-playbook playbooks/apache-backup.yml --limit dev-hk
```

## 📋 详细说明

### Playbook工作流程

1. **环境检查**: 检查本地目录和远程Apache配置目录
2. **创建备份**: 在远程主机上将`/etc/httpd/conf`打包成ZIP
3. **下载文件**: 将ZIP文件下载到本地`downloads/`目录
4. **解压文件**: 解压到`extracted/主机名/`目录
5. **Git操作**: 克隆/更新GitHub仓库
6. **推送配置**: 将配置文件推送到对应分支
7. **清理**: 清理临时文件

### 变量说明

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `backup_dir` | 远程备份目录 | `/tmp/apache_backup` |
| `local_download_dir` | 本地下载目录 | `./downloads` |
| `local_extract_dir` | 本地解压目录 | `./extracted` |
| `github_repo` | GitHub仓库地址 | 需要配置 |
| `github_token` | GitHub访问令牌 | 需要配置 |

### 目录映射

- 远程主机 → 本地 → GitHub分支
- `/etc/httpd/conf` → `extracted/主机名/` → `github-repo/分支名/`

## 🔧 高级配置

### 1. 自定义备份目录

修改`group_vars/all.yml`：

```yaml
backup_dir: /your/custom/backup/path
```

### 2. 添加更多主机

在`inventory/hosts.yml`中添加新主机：

```yaml
        new-server:
          ansible_host: 192.168.1.40
          ansible_user: admin
          github_branch: new-server
```

### 3. 使用不同的SSH密钥

为特定主机指定SSH密钥：

```yaml
        special-server:
          ansible_host: 192.168.1.50
          ansible_user: root
          ansible_ssh_private_key_file: ~/.ssh/special_key
          github_branch: special
```

## 🔍 故障排除

### 常见问题

1. **SSH连接失败**
   ```bash
   # 测试SSH连接
   ansible all -m ping
   ```

2. **权限不足**
   ```bash
   # 确保用户有sudo权限或使用root用户
   ansible-playbook playbooks/apache-backup.yml --ask-become-pass
   ```

3. **GitHub推送失败**
   - 检查GitHub token是否有效
   - 确保仓库存在且有推送权限
   - 检查分支是否存在

4. **GitHub认证失败**
   - 检查GitHub token是否正确配置在`group_vars/all.yml`中
   - 确保token有足够的权限

### 调试模式

使用详细输出进行调试：

```bash
ansible-playbook playbooks/apache-backup.yml -vvv
```

## 🔒 安全注意事项

1. **保护敏感信息**: 不要将包含真实GitHub token的配置文件提交到公开仓库
2. **限制SSH访问**: 使用SSH密钥而非密码
3. **GitHub token权限**: 仅授予必要的仓库权限
4. **定期更新**: 定期更新Ansible和依赖包

## 📈 扩展功能

### 定时任务

使用crontab设置定时备份：

```bash
# 每天凌晨2点执行备份
0 2 * * * cd /path/to/ansible-rproxy && ./run-backup.sh >> /var/log/apache-backup.log 2>&1
```

### 通知功能

在playbook中添加邮件或Slack通知任务来报告备份状态。

### 多环境支持

创建不同的inventory文件来支持开发、测试、生产环境。

## 📞 支持

如果遇到问题，请检查：
1. Ansible版本兼容性
2. 网络连接状态
3. 权限配置
4. GitHub API限制

## 🏢 Ansible Tower集成

本项目已针对Ansible Tower进行了优化，提供企业级的自动化执行能力。

### Tower优化特性

#### 🔒 **凭据管理**
- SSH密钥通过Tower凭据系统管理
- GitHub token安全存储
- 支持多环境凭据隔离

#### 📊 **任务模板**
- `apache-backup-tower.yml` - Tower优化的备份playbook
- `git-push-tower.yml` - 专用Git推送任务
- `apache-backup-complete-tower.yml` - 完整流程集成

#### 🔄 **工作流支持**
- 备份 → Git推送的自动化工作流
- 并行执行控制 (`serial` 参数)
- 失败处理和回滚机制

#### 📋 **Survey集成**
- 动态主机选择
- 灵活的分支配置
- 用户友好的参数输入

### 快速配置

```bash
# 1. 查看Tower配置指南
cat TOWER_SETUP.md

# 2. 使用Tower优化的playbook
ansible-playbook playbooks/apache-backup-tower.yml

# 3. 完整流程（推荐）
ansible-playbook playbooks/apache-backup-complete-tower.yml
```

### Tower配置要点

| 配置项 | 说明 | 建议值 |
|--------|------|--------|
| **凭据类型** | Machine + Source Control | SSH + GitHub |
| **执行环境** | 支持Git和SSH的容器 | Default EE |
| **并发策略** | Serial执行控制 | `backup_serial: 2` |
| **Survey变量** | 动态参数配置 | 主机选择 + 分支名 |

详细配置说明请参见：[**TOWER_SETUP.md**](TOWER_SETUP.md)

### 企业环境建议

- ✅ 使用Ansible Tower进行生产部署
- ✅ 配置通知和监控
- ✅ 实施访问控制和审计
- ✅ 定期备份Tower配置

---

**注意**: 请根据您的实际环境修改配置文件中的IP地址、用户名、仓库信息等参数。

🎯 **项目目标**: 提供一个简单、可靠、自动化的Apache配置备份解决方案  
🏢 **企业级**: 完整支持Ansible Tower企业自动化平台 