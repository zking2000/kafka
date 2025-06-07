# HAProxy Ansible自动化部署

这个Ansible项目用于在VM上自动安装和配置HAProxy，用作Kafka集群的负载均衡器和mTLS代理。

## 文件结构

```
ansible/
├── ansible.cfg              # Ansible配置文件
├── inventory.yml            # 主机清单文件
├── haproxy-install.yml      # HAProxy安装和配置playbook
├── test-connection.yml      # 连接测试playbook
├── templates/
│   └── haproxy.cfg.j2      # HAProxy配置文件模板
└── README.md               # 本说明文件
```

## 使用前准备

### 1. 安装Ansible

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install ansible

# macOS
brew install ansible

# CentOS/RHEL
sudo yum install ansible
```

### 2. 配置SSH密钥

确保你可以通过SSH密钥无密码登录到目标VM：

```bash
# 生成SSH密钥（如果还没有）
ssh-keygen -t rsa -b 4096

# 将公钥复制到目标VM
ssh-copy-id username@your-vm-ip
```

### 3. 修改主机清单

编辑 `inventory.yml` 文件，更新以下信息：
- `ansible_host`: 目标VM的IP地址
- `ansible_user`: SSH用户名
- `ansible_ssh_private_key_file`: SSH私钥路径
- `kafka_brokers`: Kafka集群的broker信息

## 使用方法

### 1. 测试连接

首先测试与目标主机的连接：

```bash
cd ansible
ansible-playbook test-connection.yml
```

### 2. 安装和配置HAProxy

运行主要的安装playbook：

```bash
ansible-playbook haproxy-install.yml
```

### 3. 验证安装

安装完成后，你可以通过以下方式验证：

```bash
# 检查HAProxy服务状态
ansible haproxy_servers -m shell -a "systemctl status haproxy"

# 测试健康检查端点
curl http://your-vm-ip/

# 访问HAProxy统计页面
# 在浏览器中打开: http://your-vm-ip:8404/stats
```

## 配置说明

### HAProxy配置

HAProxy将配置以下端口：
- `80`: 健康检查端点，返回 "Kafka-Proxy-OK"
- `8404`: HAProxy统计页面
- `19094`: Kafka broker-0 (kafka-0) 的mTLS代理端口
- `29094`: Kafka broker-1 (kafka-1) 的mTLS代理端口  
- `39094`: Kafka broker-2 (kafka-2) 的mTLS代理端口

### Kafka集群配置

默认配置连接到以下Kafka brokers：
- kafka-0: 10.0.0.31:9094
- kafka-1: 10.0.0.30:9094
- kafka-2: 10.0.0.32:9094

如需修改，请编辑 `inventory.yml` 文件中的 `kafka_brokers` 变量。

## 故障排除

### 1. 连接问题

如果无法连接到目标主机：
- 检查SSH密钥配置
- 确认目标主机IP地址正确
- 检查防火墙设置

### 2. 权限问题

如果出现权限错误：
- 确保SSH用户有sudo权限
- 检查 `ansible.cfg` 中的权限提升设置

### 3. HAProxy启动失败

如果HAProxy服务启动失败：
- 检查配置文件语法：`haproxy -c -f /etc/haproxy/haproxy.cfg`
- 查看服务日志：`journalctl -u haproxy -f`
- 确认端口没有被其他服务占用

## 自定义配置

### 修改HAProxy配置

如需自定义HAProxy配置，请编辑 `templates/haproxy.cfg.j2` 文件。

### 添加更多主机

在 `inventory.yml` 的 `haproxy_servers.hosts` 下添加更多VM配置。

### 修改Kafka集群信息

更新 `inventory.yml` 中的 `kafka_brokers` 变量以匹配你的Kafka集群配置。

## 安全注意事项

1. 确保SSH密钥文件的权限设置正确（600）
2. 定期更新HAProxy版本以获取安全补丁
3. 考虑为HAProxy统计页面添加认证
4. 确保防火墙只开放必要的端口 
