#!/bin/bash

#==============================================================================
# Splunk Universal Forwarder 回滚脚本
# 功能：从备份恢复Splunk Universal Forwarder配置
# 作者：System Administrator
# 版本：1.0
#==============================================================================

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 配置变量
SPLUNK_HOME="/opt/splunkforwarder"
SPLUNK_USER="splunk"
BACKUP_DIR=""
LOG_FILE="/tmp/splunk_rollback_$(date +%Y%m%d_%H%M%S).log"

# 日志函数
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# 使用说明
usage() {
    cat << EOF
使用方法: $0 -b <backup_directory> [选项]

必需参数:
  -b, --backup-dir <path>   备份目录路径

可选参数:
  -h, --home <path>         Splunk安装目录 (默认: $SPLUNK_HOME)
  -u, --user <user>         Splunk服务用户 (默认: $SPLUNK_USER)
  --help                   显示此帮助信息

示例:
  $0 -b /tmp/splunk_backup_20231201_120000
  $0 -b /backup/splunk -h /opt/splunk -u splunk

EOF
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "此脚本需要root权限运行"
        log "ERROR" "请使用: sudo $0 $*"
        exit 1
    fi
    log "INFO" "权限检查通过"
}

# 检查参数
check_arguments() {
    if [[ -z "$BACKUP_DIR" ]]; then
        log "ERROR" "必须指定备份目录"
        usage
        exit 1
    fi
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log "ERROR" "备份目录不存在: $BACKUP_DIR"
        exit 1
    fi
    
    if [[ ! -d "$BACKUP_DIR/etc" ]]; then
        log "ERROR" "备份目录中未找到etc配置目录: $BACKUP_DIR/etc"
        exit 1
    fi
    
    log "INFO" "参数检查通过"
    log "INFO" "备份目录: $BACKUP_DIR"
    log "INFO" "Splunk目录: $SPLUNK_HOME"
}

# 显示备份信息
show_backup_info() {
    log "INFO" "显示备份信息..."
    
    if [[ -f "$BACKUP_DIR/backup_info.txt" ]]; then
        log "INFO" "备份信息文件内容:"
        cat "$BACKUP_DIR/backup_info.txt" | while read line; do
            log "INFO" "  $line"
        done
    fi
    
    if [[ -f "$BACKUP_DIR/version_before_upgrade.txt" ]]; then
        local version_info
        version_info=$(head -1 "$BACKUP_DIR/version_before_upgrade.txt" 2>/dev/null || echo "未知版本")
        log "INFO" "备份时的版本: $version_info"
    fi
}

# 停止Splunk服务
stop_splunk() {
    log "INFO" "停止Splunk服务..."
    
    if [[ -f "$SPLUNK_HOME/bin/splunk" ]]; then
        if $SPLUNK_HOME/bin/splunk stop 2>/dev/null; then
            log "INFO" "Splunk服务已停止"
        else
            log "WARN" "停止Splunk服务失败或服务未运行"
        fi
        
        # 等待端口释放
        local count=0
        while netstat -tuln 2>/dev/null | grep -q ":8089 " && [[ $count -lt 30 ]]; do
            log "INFO" "等待端口8089释放..."
            sleep 2
            ((count++))
        done
    else
        log "WARN" "未找到Splunk二进制文件"
    fi
}

# 备份当前配置（以防回滚失败）
backup_current_config() {
    local current_backup_dir="/tmp/splunk_before_rollback_$(date +%Y%m%d_%H%M%S)"
    
    if [[ -d "$SPLUNK_HOME/etc" ]]; then
        log "INFO" "备份当前配置到: $current_backup_dir"
        mkdir -p "$current_backup_dir"
        cp -r "$SPLUNK_HOME/etc" "$current_backup_dir/"
        
        cat > "$current_backup_dir/rollback_info.txt" << EOF
回滚前备份时间: $(date)
原备份目录: $BACKUP_DIR
当前Splunk目录: $SPLUNK_HOME
回滚日志: $LOG_FILE
EOF
        log "INFO" "当前配置已备份到: $current_backup_dir"
    fi
}

# 恢复配置
restore_configuration() {
    log "INFO" "开始恢复配置..."
    
    # 删除当前etc目录
    if [[ -d "$SPLUNK_HOME/etc" ]]; then
        log "INFO" "删除当前配置目录..."
        rm -rf "$SPLUNK_HOME/etc"
    fi
    
    # 恢复备份的配置
    log "INFO" "恢复配置文件..."
    cp -r "$BACKUP_DIR/etc" "$SPLUNK_HOME/"
    
    # 设置正确的权限
    log "INFO" "设置文件权限..."
    chown -R "$SPLUNK_USER:$SPLUNK_USER" "$SPLUNK_HOME/etc"
    
    log "INFO" "配置恢复完成"
}

# 启动Splunk服务
start_splunk() {
    log "INFO" "启动Splunk服务..."
    
    if su - "$SPLUNK_USER" -c "$SPLUNK_HOME/bin/splunk start --accept-license --answer-yes --no-prompt"; then
        log "INFO" "Splunk服务启动成功"
        
        # 等待服务启动
        local count=0
        while ! netstat -tuln 2>/dev/null | grep -q ":8089 " && [[ $count -lt 60 ]]; do
            log "INFO" "等待服务启动..."
            sleep 2
            ((count++))
        done
        
        if [[ $count -ge 60 ]]; then
            log "WARN" "服务启动超时，请手动检查"
        else
            log "INFO" "服务已成功启动"
        fi
    else
        log "ERROR" "启动Splunk服务失败"
        return 1
    fi
}

# 验证回滚结果
verify_rollback() {
    log "INFO" "验证回滚结果..."
    
    # 检查版本
    if [[ -f "$SPLUNK_HOME/bin/splunk" ]]; then
        local current_version
        current_version=$($SPLUNK_HOME/bin/splunk version --accept-license --answer-yes --no-prompt 2>/dev/null | head -1 || echo "无法获取版本")
        log "INFO" "当前版本: $current_version"
    fi
    
    # 检查服务状态
    local service_status
    if service_status=$($SPLUNK_HOME/bin/splunk status 2>/dev/null); then
        log "INFO" "服务状态: $service_status"
    else
        log "WARN" "无法获取服务状态"
    fi
    
    # 检查转发器配置
    if $SPLUNK_HOME/bin/splunk list forward-server 2>/dev/null; then
        log "INFO" "转发器配置验证成功"
    else
        log "WARN" "无法验证转发器配置"
    fi
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -h|--home)
            SPLUNK_HOME="$2"
            shift 2
            ;;
        -u|--user)
            SPLUNK_USER="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            log "ERROR" "未知参数: $1"
            usage
            exit 1
            ;;
    esac
done

# 主函数
main() {
    log "INFO" "=========================================="
    log "INFO" "Splunk Universal Forwarder 回滚开始"
    log "INFO" "=========================================="
    
    check_root "$@"
    check_arguments
    show_backup_info
    
    # 确认回滚
    echo
    echo -e "${YELLOW}即将回滚Splunk Universal Forwarder配置${NC}"
    echo -e "备份目录: ${BLUE}$BACKUP_DIR${NC}"
    echo -e "Splunk目录: ${BLUE}$SPLUNK_HOME${NC}"
    echo
    echo -e "${RED}警告: 这将覆盖当前的所有配置！${NC}"
    echo
    read -p "确认继续回滚？(y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "用户取消回滚操作"
        exit 0
    fi
    
    # 执行回滚步骤
    if stop_splunk && \
       backup_current_config && \
       restore_configuration && \
       start_splunk && \
       verify_rollback; then
        
        log "INFO" "=========================================="
        log "INFO" "Splunk Universal Forwarder 回滚成功完成！"
        log "INFO" "=========================================="
        log "INFO" "日志文件: $LOG_FILE"
        
    else
        log "ERROR" "回滚过程中发生错误"
        log "ERROR" "请检查日志文件: $LOG_FILE"
        exit 1
    fi
}

# 执行主函数
main "$@" 