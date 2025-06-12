#!/bin/bash

# Ansible Inventory更新脚本
# 从Terraform输出自动更新Ansible主机清单

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置文件路径
TERRAFORM_DIR="./terraform"
INVENTORY_FILE="./inventory/tower-hosts.yml"
BACKUP_INVENTORY="./inventory/tower-hosts.yml.backup"

echo -e "${GREEN}🔄 Ansible Inventory更新工具${NC}"
echo ""

# 检查必要文件和目录
check_prerequisites() {
    echo -e "${BLUE}🔍 检查必要文件...${NC}"
    
    if [ ! -d "$TERRAFORM_DIR" ]; then
        echo -e "${RED}❌ Terraform目录不存在: $TERRAFORM_DIR${NC}"
        exit 1
    fi
    
    if [ ! -f "$TERRAFORM_DIR/terraform.tfstate" ]; then
        echo -e "${RED}❌ Terraform状态文件不存在，请先运行terraform apply${NC}"
        exit 1
    fi
    
    if [ ! -f "$INVENTORY_FILE" ]; then
        echo -e "${YELLOW}⚠️  Inventory文件不存在，将创建新文件${NC}"
        mkdir -p "$(dirname "$INVENTORY_FILE")"
    else
        echo -e "${BLUE}📝 备份现有inventory文件...${NC}"
        cp "$INVENTORY_FILE" "$BACKUP_INVENTORY"
        echo -e "${GREEN}✅ 备份完成: $BACKUP_INVENTORY${NC}"
    fi
    
    echo -e "${GREEN}✅ 文件检查完成${NC}"
}

# 从Terraform获取主机信息
get_terraform_output() {
    echo -e "${BLUE}📊 获取Terraform输出信息...${NC}"
    
    cd "$TERRAFORM_DIR"
    
    # 检查Terraform输出是否可用
    if ! terraform output &>/dev/null; then
        echo -e "${RED}❌ 无法获取Terraform输出，请确保已成功部署${NC}"
        exit 1
    fi
    
    # 获取JSON格式的输出
    TF_OUTPUT=$(terraform output -json)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ 获取Terraform输出失败${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Terraform输出获取成功${NC}"
    cd - > /dev/null
}

# 生成新的inventory文件
generate_inventory() {
    echo -e "${BLUE}📝 生成新的inventory文件...${NC}"
    
    # 解析Terraform输出
    local instance_names=$(echo "$TF_OUTPUT" | jq -r '.instance_names.value[]' 2>/dev/null || echo "")
    local external_ips=$(echo "$TF_OUTPUT" | jq -r '.instance_external_ips.value[]' 2>/dev/null || echo "")
    local internal_ips=$(echo "$TF_OUTPUT" | jq -r '.instance_internal_ips.value[]' 2>/dev/null || echo "")
    local environment=$(echo "$TF_OUTPUT" | jq -r '.deployment_summary.value.environment' 2>/dev/null || echo "dev")
    local ssh_user=$(echo "$TF_OUTPUT" | jq -r '.deployment_summary.value.ssh_user // "rocky"' 2>/dev/null || echo "rocky")
    
    if [ -z "$instance_names" ] || [ -z "$external_ips" ]; then
        echo -e "${RED}❌ 无法从Terraform输出获取实例信息${NC}"
        echo "请确保Terraform部署成功并包含正确的输出定义"
        exit 1
    fi
    
    # 创建新的Tower优化inventory文件
    cat > "$INVENTORY_FILE" << EOF
---
# Ansible Tower Inventory - 由update-inventory.sh自动生成
# 生成时间: $(date)
# 环境: $environment
# Tower优化版本

all:
  children:
    rproxy:
      hosts:
EOF

    # 将实例信息转换为数组
    local names_array=($instance_names)
    local external_ips_array=($external_ips)
    local internal_ips_array=($internal_ips)
    
    # 为每个实例生成inventory条目
    for i in "${!names_array[@]}"; do
        local instance_name="${names_array[$i]}"
        local external_ip="${external_ips_array[$i]}"
        local internal_ip="${internal_ips_array[$i]}"
        local host_alias="${environment}-$(echo $instance_name | sed 's/.*-rproxy-/rproxy-/')"
        
        cat >> "$INVENTORY_FILE" << EOF
        $host_alias:
          ansible_host: $external_ip
          ansible_user: $ssh_user
          ansible_ssh_private_key_file: "~/.ssh/google_compute_engine"
          ansible_port: 2234
          github_branch: $host_alias
          instance_name: $instance_name
          internal_ip: $internal_ip
          environment: $environment
EOF
    done
    
    # 添加Tower优化的组变量
    cat >> "$INVENTORY_FILE" << EOF
      vars:
        # Tower专用变量配置
        ansible_python_interpreter: /usr/bin/python3
        
        # 备份配置 - 可在Tower Job Template中覆盖
        backup_dir: "/tmp/apache_backup"
        
        # 通过Tower的Extra Variables或Survey配置这些变量
        # github_repo: 在Tower中配置
        # github_token: 在Tower Credentials中配置
        # git_user_name: 在Tower中配置
        # git_user_email: 在Tower中配置
        
        # SSH配置 - Tower会自动处理
        ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
        ansible_ssh_pipelining: yes
        ansible_ssh_timeout: 30

  vars:
    # 全局变量
    environment: $environment
    terraform_managed: true
    last_updated: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    tower_optimized: true
EOF

    echo -e "${GREEN}✅ Inventory文件生成完成${NC}"
}

# 验证生成的inventory文件
validate_inventory() {
    echo -e "${BLUE}🔧 验证inventory文件...${NC}"
    
    # 使用ansible-inventory验证语法
    if command -v ansible-inventory &> /dev/null; then
        if ansible-inventory -i "$INVENTORY_FILE" --list &> /dev/null; then
            echo -e "${GREEN}✅ Inventory文件语法正确${NC}"
        else
            echo -e "${RED}❌ Inventory文件语法错误${NC}"
            echo "正在恢复备份文件..."
            if [ -f "$BACKUP_INVENTORY" ]; then
                mv "$BACKUP_INVENTORY" "$INVENTORY_FILE"
                echo -e "${YELLOW}⚠️  已恢复原inventory文件${NC}"
            fi
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠️  ansible-inventory命令不可用，跳过语法验证${NC}"
    fi
}

# 显示更新后的主机信息
show_host_info() {
    echo -e "${BLUE}📋 更新后的主机信息:${NC}"
    echo ""
    
    if command -v ansible-inventory &> /dev/null; then
        echo -e "${YELLOW}主机列表:${NC}"
        ansible-inventory -i "$INVENTORY_FILE" --list --yaml | grep -A 5 -B 5 "ansible_host" || true
        echo ""
        
        echo -e "${YELLOW}可用主机:${NC}"
        ansible-inventory -i "$INVENTORY_FILE" --list | jq -r '.rproxy.hosts | keys[]' 2>/dev/null || echo "请安装jq以获得更好的输出格式"
    else
        echo -e "${YELLOW}主机配置已更新到: $INVENTORY_FILE${NC}"
        echo "请手动检查文件内容或安装ansible来验证配置"
    fi
}

# 测试连接（可选）
test_connections() {
    echo ""
    read -p "是否测试SSH连接到新主机？(y/N): " test_conn
    
    if [ "$test_conn" == "y" ] || [ "$test_conn" == "Y" ]; then
        echo -e "${BLUE}🌐 测试主机连接...${NC}"
        
        if command -v ansible &> /dev/null; then
            echo "正在ping所有主机..."
            if ansible -i "$INVENTORY_FILE" rproxy -m ping -o; then
                echo -e "${GREEN}✅ 所有主机连接成功${NC}"
            else
                echo -e "${YELLOW}⚠️  部分主机连接失败，这可能需要等待VM完全启动${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  Ansible未安装，无法测试连接${NC}"
        fi
    fi
}

# 显示后续操作建议
show_next_steps() {
    echo ""
    echo -e "${BLUE}📌 后续操作建议:${NC}"
    echo -e "${BLUE}1. 检查inventory文件: cat $INVENTORY_FILE${NC}"
    echo -e "${BLUE}2. 测试Ansible连接: ansible -i $INVENTORY_FILE rproxy -m ping${NC}"
    echo -e "${BLUE}3. 运行Apache备份: ./run-backup.sh${NC}"
    echo -e "${BLUE}4. 如需回滚inventory: mv $BACKUP_INVENTORY $INVENTORY_FILE${NC}"
    echo ""
}

# 清理临时文件
cleanup() {
    # 如果一切正常，可以删除备份文件（可选）
    if [ -f "$BACKUP_INVENTORY" ]; then
        read -p "是否删除备份文件 $BACKUP_INVENTORY？(y/N): " remove_backup
        if [ "$remove_backup" == "y" ] || [ "$remove_backup" == "Y" ]; then
            rm "$BACKUP_INVENTORY"
            echo -e "${GREEN}✅ 备份文件已删除${NC}"
        else
            echo -e "${BLUE}📁 备份文件保留在: $BACKUP_INVENTORY${NC}"
        fi
    fi
}

# 主函数
main() {
    echo -e "${BLUE}这个脚本将从Terraform输出自动更新Ansible inventory文件${NC}"
    echo ""
    
    check_prerequisites
    get_terraform_output
    generate_inventory
    validate_inventory
    show_host_info
    test_connections
    show_next_steps
    cleanup
    
    echo -e "${GREEN}🎉 Inventory更新完成！${NC}"
}

# 执行主函数
main "$@" 