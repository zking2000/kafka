#!/bin/bash

#==============================================================================
# Splunk Universal Forwarder 升级脚本
# 功能：自动化升级Splunk Universal Forwarder
# 作者：44084750
# 版本：1.0
# 日期：$(date +%Y-%m-%d)
#==============================================================================

set -euo pipefail  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
SPLUNK_HOME="/opt/splunkforwarder"
SPLUNK_USER="splunk"
BACKUP_DIR="/tmp/splunk_backup_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/tmp/splunk_upgrade_$(date +%Y%m%d_%H%M%S).log"
INSTALL_USER="root"
NEW_PACKAGE=""
CLEANUP_ON_SUCCESS=true

# Nexus服务器配置
NEXUS_BASE_URL="http://nexus302:8081/repository/splunk"
SPLUNK_VERSION=""
DOWNLOAD_PACKAGE=""
DOWNLOAD_TO_LOCAL=false
LOCAL_DOWNLOAD_DIR="/tmp"

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
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# 显示使用方法
usage() {
    cat << EOF
使用方法: $0 [选项]

安装包来源 (二选一):
  -f, --file <file>         本地Splunk安装包路径
  -v, --version <version>   从Nexus下载指定版本 (如: 9.1.2)

可选参数:
  -h, --home <path>         Splunk安装目录 (默认: $SPLUNK_HOME)
  -u, --user <user>         Splunk服务用户 (默认: $SPLUNK_USER)
  -b, --backup-dir <path>   备份目录 (默认: $BACKUP_DIR)
  --nexus-url <url>         Nexus服务器地址 (默认: $NEXUS_BASE_URL)
  --download-dir <path>     下载目录 (默认: $LOCAL_DOWNLOAD_DIR)
  --no-cleanup             升级成功后不清理临时文件
  --help                   显示此帮助信息

示例:
  # 从Nexus下载并升级到指定版本
  $0 -v 9.1.2
  
  # 使用本地安装包
  $0 -f /path/to/splunkforwarder-9.1.2-xxx.tgz
  
  # 自定义Nexus地址和下载目录
  $0 -v 9.1.3 --nexus-url http://nexus302:8081/repository/splunk --download-dir /opt/downloads
  
  # 完整参数示例
  $0 -v 9.1.2 -h /opt/splunk -u splunk --no-cleanup

可用版本示例: 9.1.2, 9.1.1, 9.0.4, 8.2.12
查看所有可用版本: $0 --list-versions

EOF
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "此脚本需要root权限运行"
        log "ERROR" "请使用: sudo $0 $*"
        exit 1
    fi
    log "INFO" "权限检查通过 - 运行用户: $(whoami)"
}

# 检查参数
check_arguments() {
    # 检查是否指定了安装包来源
    if [[ -z "$NEW_PACKAGE" && -z "$SPLUNK_VERSION" ]]; then
        log "ERROR" "必须指定安装包文件(-f)或版本号(-v)"
        usage
        exit 1
    fi
    
    # 如果两个都指定了，提示冲突
    if [[ -n "$NEW_PACKAGE" && -n "$SPLUNK_VERSION" ]]; then
        log "ERROR" "不能同时指定本地文件(-f)和版本号(-v)，请选择其中一种方式"
        usage
        exit 1
    fi
    
    # 检查本地文件
    if [[ -n "$NEW_PACKAGE" ]]; then
        if [[ ! -f "$NEW_PACKAGE" ]]; then
            log "ERROR" "安装包文件不存在: $NEW_PACKAGE"
            exit 1
        fi
        log "INFO" "使用本地安装包: $NEW_PACKAGE"
    fi
    
    # 检查版本号
    if [[ -n "$SPLUNK_VERSION" ]]; then
        if [[ ! "$SPLUNK_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            log "ERROR" "版本号格式不正确，应为 x.y.z 格式，如: 9.1.2"
            exit 1
        fi
        log "INFO" "将从Nexus下载版本: $SPLUNK_VERSION"
        DOWNLOAD_TO_LOCAL=true
    fi
    
    if [[ ! -d "$SPLUNK_HOME" ]]; then
        log "ERROR" "Splunk目录不存在: $SPLUNK_HOME"
        exit 1
    fi
    
    log "INFO" "参数检查通过"
    log "INFO" "Splunk目录: $SPLUNK_HOME"
    log "INFO" "服务用户: $SPLUNK_USER"
}

# 检查当前版本
check_current_version() {
    log "INFO" "检查当前Splunk版本..."
    
    if [[ -f "$SPLUNK_HOME/bin/splunk" ]]; then
        local current_version
        current_version=$($SPLUNK_HOME/bin/splunk version --accept-license --answer-yes --no-prompt 2>/dev/null | head -1 || echo "未知版本")
        log "INFO" "当前版本: $current_version"
        return 0
    else
        log "WARN" "未找到现有的Splunk安装"
        return 1
    fi
}

# 检查服务状态
check_service_status() {
    log "INFO" "检查Splunk服务状态..."
    
    local status_output
    if status_output=$($SPLUNK_HOME/bin/splunk status 2>/dev/null); then
        log "INFO" "服务状态: $status_output"
        return 0
    else
        log "WARN" "无法获取服务状态"
        return 1
    fi
}

# 从配置文件读取版本信息
load_version_config() {
    local config_file="splunk_versions.conf"
    local script_dir="$(dirname "$0")"
    local config_path="${script_dir}/${config_file}"
    
    # 检查配置文件是否存在
    if [[ ! -f "$config_path" ]]; then
        log "WARN" "版本配置文件不存在: $config_path"
        log "WARN" "将使用内置版本映射"
        return 1
    fi
    
    log "DEBUG" "加载版本配置文件: $config_path"
    return 0
}

# 获取版本对应的build号
get_build_number() {
    local version=$1
    local script_dir="$(dirname "$0")"
    local config_path="${script_dir}/splunk_versions.conf"
    
    # 如果配置文件存在，尝试从中读取
    if [[ -f "$config_path" ]]; then
        local build
        build=$(grep "^${version}=" "$config_path" 2>/dev/null | cut -d'=' -f2)
        if [[ -n "$build" ]]; then
            echo "$build"
            return 0
        fi
    fi
    
    # 如果配置文件不存在或没找到版本，使用内置映射
    log "DEBUG" "使用内置版本映射查找 $version"
    case $version in
        "9.1.2") echo "b6b9c8185839" ;;
        "9.1.1") echo "64e843ea36b1" ;;
        "9.1.0") echo "1c86ca0bacc3" ;;
        "9.0.4") echo "de405f4a7979" ;;
        "9.0.3") echo "dd0128b1f8cd" ;;
        "8.2.12") echo "6d2e146b2654" ;;
        "8.2.11") echo "a616a48d5b7b" ;;
        "8.2.10") echo "417f2e12614a" ;;
        *) 
            log "WARN" "未知版本 $version"
            echo "unknown"
            return 1
            ;;
    esac
}

# 生成下载文件名
generate_package_name() {
    local version=$1
    local arch="Linux-x86_64"
    
    local build
    build=$(get_build_number "$version")
    
    if [[ "$build" == "unknown" ]]; then
        log "ERROR" "无法获取版本 $version 的build号"
        log "ERROR" "请检查版本号是否正确，或更新 splunk_versions.conf 文件"
        return 1
    fi
    
    echo "splunkforwarder-${version}-${build}-${arch}.tgz"
}

# 列出所有可用版本
list_available_versions() {
    local script_dir="$(dirname "$0")"
    local config_path="${script_dir}/splunk_versions.conf"
    
    echo -e "${BLUE}=== Splunk Universal Forwarder 可用版本 ===${NC}"
    echo
    
    if [[ -f "$config_path" ]]; then
        echo -e "${GREEN}从配置文件读取版本信息:${NC} $config_path"
        echo
        
        # 按版本系列分组显示
        echo -e "${YELLOW}Splunk 9.x 系列:${NC}"
        grep "^9\." "$config_path" | grep -v "^#" | while IFS='=' read -r version build; do
            [[ -n "$version" && -n "$build" ]] && echo "  - $version (build: $build)"
        done
        echo
        
        echo -e "${YELLOW}Splunk 8.x 系列:${NC}"
        grep "^8\." "$config_path" | grep -v "^#" | while IFS='=' read -r version build; do
            [[ -n "$version" && -n "$build" ]] && echo "  - $version (build: $build)"
        done
        echo
    else
        echo -e "${YELLOW}配置文件不存在，显示内置版本:${NC}"
        echo
        echo -e "${YELLOW}Splunk 9.x 系列:${NC}"
        echo "  - 9.1.2 (build: b6b9c8185839)"
        echo "  - 9.1.1 (build: 64e843ea36b1)"
        echo "  - 9.1.0 (build: 1c86ca0bacc3)"
        echo "  - 9.0.4 (build: de405f4a7979)"
        echo "  - 9.0.3 (build: dd0128b1f8cd)"
        echo
        echo -e "${YELLOW}Splunk 8.x 系列:${NC}"
        echo "  - 8.2.12 (build: 6d2e146b2654)"
        echo "  - 8.2.11 (build: a616a48d5b7b)"
        echo "  - 8.2.10 (build: 417f2e12614a)"
        echo
    fi
    
    echo -e "${GREEN}使用示例:${NC}"
    echo "  $0 -v 9.1.2"
    echo "  $0 -v 8.2.12"
    echo
    echo -e "${BLUE}注意:${NC} 新版本可通过编辑 splunk_versions.conf 文件添加"
}

# 从Nexus下载安装包
download_package() {
    if [[ "$DOWNLOAD_TO_LOCAL" != "true" ]]; then
        return 0
    fi
    
    log "INFO" "准备从Nexus下载Splunk Universal Forwarder..."
    
    # 确保下载目录存在
    mkdir -p "$LOCAL_DOWNLOAD_DIR"
    
    # 生成下载文件名
    local package_name
    package_name=$(generate_package_name "$SPLUNK_VERSION")
    log "INFO" "预期包名: $package_name"
    
    # 构建下载URL
    local download_url="${NEXUS_BASE_URL}/${package_name}"
    local local_file_path="${LOCAL_DOWNLOAD_DIR}/${package_name}"
    
    log "INFO" "下载URL: $download_url"
    log "INFO" "本地路径: $local_file_path"
    
    # 检查文件是否已存在
    if [[ -f "$local_file_path" ]]; then
        log "INFO" "文件已存在，检查文件完整性..."
        if [[ -s "$local_file_path" ]]; then
            log "INFO" "使用已存在的文件: $local_file_path"
            NEW_PACKAGE="$local_file_path"
            return 0
        else
            log "WARN" "已存在文件为空，重新下载..."
            rm -f "$local_file_path"
        fi
    fi
    
    # 执行下载
    log "INFO" "开始下载..."
    if command -v wget >/dev/null 2>&1; then
        if wget --progress=bar:force --timeout=300 -O "$local_file_path" "$download_url" 2>&1 | tee -a "$LOG_FILE"; then
            log "INFO" "wget下载成功"
        else
            log "ERROR" "wget下载失败"
            rm -f "$local_file_path"
            return 1
        fi
    elif command -v curl >/dev/null 2>&1; then
        if curl -L --progress-bar --connect-timeout 300 -o "$local_file_path" "$download_url"; then
            log "INFO" "curl下载成功"
        else
            log "ERROR" "curl下载失败"
            rm -f "$local_file_path"
            return 1
        fi
    else
        log "ERROR" "系统中未找到wget或curl命令，无法下载文件"
        return 1
    fi
    
    # 验证下载的文件
    if [[ ! -f "$local_file_path" ]]; then
        log "ERROR" "下载后文件不存在: $local_file_path"
        return 1
    fi
    
    if [[ ! -s "$local_file_path" ]]; then
        log "ERROR" "下载的文件为空: $local_file_path"
        rm -f "$local_file_path"
        return 1
    fi
    
    # 检查文件是否是有效的tar.gz文件
    if ! tar -tzf "$local_file_path" >/dev/null 2>&1; then
        log "ERROR" "下载的文件不是有效的tar.gz格式"
        rm -f "$local_file_path"
        return 1
    fi
    
    local file_size
    file_size=$(ls -lh "$local_file_path" | awk '{print $5}')
    log "INFO" "下载完成，文件大小: $file_size"
    
    # 设置NEW_PACKAGE变量
    NEW_PACKAGE="$local_file_path"
    log "INFO" "下载的安装包路径: $NEW_PACKAGE"
    
    return 0
}

# 停止Splunk服务
stop_splunk() {
    log "INFO" "停止Splunk服务..."
    
    if $SPLUNK_HOME/bin/splunk stop; then
        log "INFO" "Splunk服务已停止"
        
        # 等待端口释放
        local port_check_count=0
        while netstat -tuln | grep -q ":8089 " && [[ $port_check_count -lt 30 ]]; do
            log "DEBUG" "等待端口8089释放..."
            sleep 2
            ((port_check_count++))
        done
        
        if [[ $port_check_count -ge 30 ]]; then
            log "WARN" "端口8089仍在使用，强制继续..."
        fi
    else
        log "ERROR" "停止Splunk服务失败"
        return 1
    fi
}

# 创建备份
create_backup() {
    log "INFO" "创建配置备份..."
    
    mkdir -p "$BACKUP_DIR"
    
    # 备份etc目录
    if [[ -d "$SPLUNK_HOME/etc" ]]; then
        log "INFO" "备份配置文件到: $BACKUP_DIR"
        cp -r "$SPLUNK_HOME/etc" "$BACKUP_DIR/"
        log "INFO" "配置文件备份完成"
    fi
    
    # 备份当前版本信息
    if [[ -f "$SPLUNK_HOME/bin/splunk" ]]; then
        $SPLUNK_HOME/bin/splunk version --accept-license --answer-yes --no-prompt > "$BACKUP_DIR/version_before_upgrade.txt" 2>/dev/null || true
    fi
    
    # 创建备份信息文件
    cat > "$BACKUP_DIR/backup_info.txt" << EOF
备份时间: $(date)
备份路径: $BACKUP_DIR
Splunk目录: $SPLUNK_HOME
升级包: $NEW_PACKAGE
日志文件: $LOG_FILE
EOF
    
    log "INFO" "备份创建完成: $BACKUP_DIR"
}

# 安装新版本
install_new_version() {
    log "INFO" "开始安装新版本..."
    
    local temp_extract_dir="/tmp/splunk_extract_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$temp_extract_dir"
    
    log "INFO" "解压安装包到临时目录: $temp_extract_dir"
    if tar -xzf "$NEW_PACKAGE" -C "$temp_extract_dir"; then
        log "INFO" "安装包解压成功"
    else
        log "ERROR" "安装包解压失败"
        return 1
    fi
    
    # 查找解压后的splunkforwarder目录
    local splunk_source_dir
    splunk_source_dir=$(find "$temp_extract_dir" -name "splunkforwarder" -type d | head -1)
    
    if [[ -z "$splunk_source_dir" ]]; then
        log "ERROR" "在解压目录中未找到splunkforwarder目录"
        rm -rf "$temp_extract_dir"
        return 1
    fi
    
    log "INFO" "找到源目录: $splunk_source_dir"
    
    # 移除旧的bin和lib目录，保留etc目录
    log "INFO" "清理旧版本文件..."
    for dir in bin lib share; do
        if [[ -d "$SPLUNK_HOME/$dir" ]]; then
            rm -rf "$SPLUNK_HOME/$dir"
            log "DEBUG" "已删除: $SPLUNK_HOME/$dir"
        fi
    done
    
    # 复制新版本文件
    log "INFO" "安装新版本文件..."
    cp -r "$splunk_source_dir"/* "$SPLUNK_HOME/"
    
    # 设置正确的权限
    log "INFO" "设置文件权限..."
    chown -R "$SPLUNK_USER:$SPLUNK_USER" "$SPLUNK_HOME"
    chmod +x "$SPLUNK_HOME/bin/splunk"
    
    # 清理临时目录
    rm -rf "$temp_extract_dir"
    
    log "INFO" "新版本安装完成"
}

# 恢复配置
restore_configuration() {
    log "INFO" "恢复配置文件..."
    
    if [[ -d "$BACKUP_DIR/etc" ]]; then
        # 确保etc目录存在
        mkdir -p "$SPLUNK_HOME/etc"
        
        # 恢复配置文件
        cp -r "$BACKUP_DIR/etc"/* "$SPLUNK_HOME/etc/"
        
        # 设置权限
        chown -R "$SPLUNK_USER:$SPLUNK_USER" "$SPLUNK_HOME/etc"
        
        log "INFO" "配置文件恢复完成"
    else
        log "WARN" "未找到配置备份，将使用默认配置"
    fi
}

# 启动Splunk服务
start_splunk() {
    log "INFO" "启动Splunk服务..."
    
    # 以splunk用户身份启动服务
    if su - "$SPLUNK_USER" -c "$SPLUNK_HOME/bin/splunk start --accept-license --answer-yes --no-prompt"; then
        log "INFO" "Splunk服务启动成功"
        
        # 等待服务完全启动
        local start_check_count=0
        while ! netstat -tuln | grep -q ":8089 " && [[ $start_check_count -lt 60 ]]; do
            log "DEBUG" "等待服务启动..."
            sleep 2
            ((start_check_count++))
        done
        
        if [[ $start_check_count -ge 60 ]]; then
            log "ERROR" "服务启动超时"
            return 1
        fi
        
        log "INFO" "服务已完全启动"
    else
        log "ERROR" "启动Splunk服务失败"
        return 1
    fi
}

# 验证升级
verify_upgrade() {
    log "INFO" "验证升级结果..."
    
    # 检查版本
    local new_version
    if new_version=$($SPLUNK_HOME/bin/splunk version --accept-license --answer-yes --no-prompt 2>/dev/null | head -1); then
        log "INFO" "升级后版本: $new_version"
    else
        log "ERROR" "无法获取升级后版本信息"
        return 1
    fi
    
    # 检查服务状态
    local service_status
    if service_status=$($SPLUNK_HOME/bin/splunk status 2>/dev/null); then
        log "INFO" "服务状态: $service_status"
    else
        log "ERROR" "无法获取服务状态"
        return 1
    fi
    
    # 检查转发器配置
    log "INFO" "检查转发器配置..."
    if $SPLUNK_HOME/bin/splunk list forward-server 2>/dev/null; then
        log "INFO" "转发器配置验证成功"
    else
        log "WARN" "无法验证转发器配置"
    fi
    
    log "INFO" "升级验证完成"
}

# 清理临时文件
cleanup() {
    if [[ "$CLEANUP_ON_SUCCESS" == "true" ]]; then
        log "INFO" "清理临时文件..."
        
        # 清理解压临时目录
        find /tmp -name "splunk_extract_*" -type d -mmin +60 -exec rm -rf {} + 2>/dev/null || true
        
        # 如果是从Nexus下载的文件，询问是否删除
        if [[ "$DOWNLOAD_TO_LOCAL" == "true" && -f "$NEW_PACKAGE" ]]; then
            echo
            echo -e "${YELLOW}下载的安装包: ${BLUE}$NEW_PACKAGE${NC}"
            read -p "是否删除下载的安装包？(y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -f "$NEW_PACKAGE"
                log "INFO" "已删除下载的安装包: $NEW_PACKAGE"
            else
                log "INFO" "保留下载的安装包: $NEW_PACKAGE"
            fi
        fi
        
        log "INFO" "临时文件清理完成"
        log "INFO" "备份保留在: $BACKUP_DIR"
        log "INFO" "日志保留在: $LOG_FILE"
    fi
}

# 回滚函数
rollback() {
    log "ERROR" "升级失败，开始回滚..."
    
    if [[ -d "$BACKUP_DIR/etc" ]]; then
        log "INFO" "恢复配置文件..."
        rm -rf "$SPLUNK_HOME/etc"
        cp -r "$BACKUP_DIR/etc" "$SPLUNK_HOME/"
        chown -R "$SPLUNK_USER:$SPLUNK_USER" "$SPLUNK_HOME/etc"
        
        log "INFO" "尝试启动服务..."
        if su - "$SPLUNK_USER" -c "$SPLUNK_HOME/bin/splunk start --accept-license --answer-yes --no-prompt" 2>/dev/null; then
            log "INFO" "回滚成功，服务已恢复"
        else
            log "ERROR" "回滚失败，请手动检查"
        fi
    else
        log "ERROR" "未找到备份文件，无法自动回滚"
    fi
}

# 信号处理
trap 'log "ERROR" "脚本被中断"; rollback; exit 1' INT TERM

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--file)
            NEW_PACKAGE="$2"
            shift 2
            ;;
        -v|--version)
            SPLUNK_VERSION="$2"
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
        -b|--backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --nexus-url)
            NEXUS_BASE_URL="$2"
            shift 2
            ;;
        --download-dir)
            LOCAL_DOWNLOAD_DIR="$2"
            shift 2
            ;;
        --no-cleanup)
            CLEANUP_ON_SUCCESS=false
            shift
            ;;
        --list-versions)
            list_available_versions
            exit 0
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

# 主要执行流程
main() {
    log "INFO" "=========================================="
    log "INFO" "Splunk Universal Forwarder 升级开始"
    log "INFO" "=========================================="
    
    # 执行各个步骤
    check_root "$@"
    load_version_config || log "DEBUG" "继续使用内置版本映射"
    check_arguments
    download_package || {
        log "ERROR" "下载安装包失败"
        exit 1
    }
    check_current_version || true
    check_service_status || true
    
    # 确认升级
    echo
    echo -e "${YELLOW}即将升级Splunk Universal Forwarder${NC}"
    if [[ -n "$SPLUNK_VERSION" ]]; then
        echo -e "目标版本: ${BLUE}$SPLUNK_VERSION${NC}"
        echo -e "下载来源: ${BLUE}$NEXUS_BASE_URL${NC}"
    fi
    echo -e "安装包: ${BLUE}$NEW_PACKAGE${NC}"
    echo -e "安装目录: ${BLUE}$SPLUNK_HOME${NC}"
    echo -e "备份目录: ${BLUE}$BACKUP_DIR${NC}"
    echo
    read -p "确认继续升级？(y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "用户取消升级操作"
        exit 0
    fi
    
    # 执行升级步骤
    if stop_splunk && \
       create_backup && \
       install_new_version && \
       restore_configuration && \
       start_splunk && \
       verify_upgrade; then
        
        cleanup
        
        log "INFO" "=========================================="
        log "INFO" "Splunk Universal Forwarder 升级成功完成！"
        log "INFO" "=========================================="
        log "INFO" "备份位置: $BACKUP_DIR"
        log "INFO" "日志文件: $LOG_FILE"
        
    else
        log "ERROR" "升级过程中发生错误"
        rollback
        exit 1
    fi
}

# 执行主函数
main "$@" 