#!/bin/bash

# Apache配置备份 - 代理连接版本
# 用法: ./run-proxy.sh [playbook] [inventory] [extra-vars]

set -e  # 遇到错误时退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认参数
PLAYBOOK="${1:-playbooks/apache-backup.yml}"
INVENTORY="${2:-inventory/hosts.yml}"
CONFIG="ansible.cfg"
EXTRA_VARS="${3:-}"

# 函数：打印彩色消息
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_message $BLUE "🔧 Apache配置备份 - 代理连接版"
print_message $BLUE "======================================="

# 检查必要文件是否存在
if [ ! -f "$PLAYBOOK" ]; then
    print_message $RED "❌ Playbook文件不存在: $PLAYBOOK"
    exit 1
fi

if [ ! -f "$INVENTORY" ]; then
    print_message $RED "❌ Inventory文件不存在: $INVENTORY"
    print_message $YELLOW "请先编辑 $INVENTORY 文件，配置您的代理服务器和目标服务器信息"
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    print_message $RED "❌ 配置文件不存在: $CONFIG"
    exit 1
fi

# 检查SSH密钥
SSH_KEY=$(grep "private_key_file" $CONFIG | cut -d'=' -f2 | xargs)
SSH_KEY_EXPANDED="${SSH_KEY/#\~/$HOME}"
if [ ! -f "$SSH_KEY_EXPANDED" ]; then
    print_message $RED "❌ SSH私钥文件不存在: $SSH_KEY_EXPANDED"
    print_message $YELLOW "请确保SSH密钥路径正确，或运行: ssh-keygen -t rsa"
    exit 1
fi

print_message $GREEN "✅ 基础检查通过"

# 代理连接测试
print_message $BLUE "🔗 正在测试代理连接..."

# 从inventory文件中提取代理信息进行连接测试
PROXY_INFO=$(grep -A 10 "ansible_ssh_common_args" $INVENTORY | grep "ProxyJump\|ProxyCommand" | head -1 || true)

if [ -n "$PROXY_INFO" ]; then
    print_message $YELLOW "⚠️  检测到代理配置，请确保："
    echo "   1. 代理服务器可以正常访问"
    echo "   2. 您的SSH密钥已添加到代理服务器和目标服务器"
    echo "   3. 代理服务器能够访问目标服务器"
    echo
    
    # 提供连接测试选项
    read -p "$(echo -e ${YELLOW}是否先测试SSH连接? [y/N]: ${NC})" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_message $BLUE "🧪 执行连接测试..."
        ANSIBLE_CONFIG=$CONFIG ansible all -i $INVENTORY -m ping --one-line || {
            print_message $RED "❌ SSH连接测试失败"
            print_message $YELLOW "请检查："
            echo "   - 代理服务器地址和端口是否正确"
            echo "   - SSH密钥是否正确配置"
            echo "   - 网络连接是否正常"
            echo "   - 防火墙设置是否允许连接"
            exit 1
        }
        print_message $GREEN "✅ SSH连接测试成功"
    fi
else
    print_message $YELLOW "⚠️  未检测到代理配置，将使用直接连接"
fi

print_message $BLUE "📋 执行参数:"
echo "   - Playbook: $PLAYBOOK"
echo "   - Inventory: $INVENTORY"
echo "   - Config: $CONFIG"
echo "   - SSH Key: $SSH_KEY"

# 检查Ansible是否安装
if ! command -v ansible-playbook &> /dev/null; then
    print_message $RED "❌ ansible-playbook未安装"
    print_message $YELLOW "请运行: pip install ansible"
    exit 1
fi

# 显示Ansible版本
ANSIBLE_VERSION=$(ansible-playbook --version | head -n1)
print_message $BLUE "🔧 $ANSIBLE_VERSION"

# 询问是否继续
read -p "$(echo -e ${YELLOW}是否继续执行? [y/N]: ${NC})" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_message $YELLOW "⚠️  执行已取消"
    exit 0
fi

print_message $GREEN "🚀 开始执行playbook..."
echo

# 构建ansible-playbook命令
ANSIBLE_CMD="ANSIBLE_CONFIG=$CONFIG ansible-playbook -i $INVENTORY $PLAYBOOK"

# 添加额外变量
if [ -n "$EXTRA_VARS" ]; then
    ANSIBLE_CMD="$ANSIBLE_CMD -e '$EXTRA_VARS'"
fi

# 添加详细输出
ANSIBLE_CMD="$ANSIBLE_CMD -v"

print_message $BLUE "执行命令: $ANSIBLE_CMD"
echo

# 执行ansible-playbook
eval $ANSIBLE_CMD

# 检查执行结果
if [ $? -eq 0 ]; then
    print_message $GREEN "✅ Playbook执行成功！"
    print_message $BLUE "📁 备份文件已保存在 ./backups/ 目录中"
    print_message $BLUE "🔗 代理连接工作正常"
else
    print_message $RED "❌ Playbook执行失败"
    print_message $YELLOW "常见代理连接问题排查："
    echo "   1. 检查代理服务器是否可访问"
    echo "   2. 验证SSH密钥配置"
    echo "   3. 确认网络防火墙设置"
    echo "   4. 查看详细错误日志"
    exit 1
fi 