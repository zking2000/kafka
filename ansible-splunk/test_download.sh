#!/bin/bash

# 测试下载功能的脚本

set -e

echo "=== 测试Splunk升级脚本的下载功能 ==="
echo

# 测试版本列表
echo "1. 测试版本列表功能:"
./upgrade_splunk_forwarder.sh --list-versions | head -10
echo

# 测试URL生成
echo "2. 测试URL生成功能:"

# 模拟脚本中的版本映射函数
get_build_number() {
    local version=$1
    local config_path="./splunk_versions.conf"
    
    if [[ -f "$config_path" ]]; then
        local build
        build=$(grep "^${version}=" "$config_path" 2>/dev/null | cut -d'=' -f2)
        if [[ -n "$build" ]]; then
            echo "$build"
            return 0
        fi
    fi
    
    case $version in
        "9.1.2") echo "b6b9c8185839" ;;
        "9.1.1") echo "64e843ea36b1" ;;
        "9.0.4") echo "de405f4a7979" ;;
        "8.2.12") echo "6d2e146b2654" ;;
        *) echo "unknown"; return 1 ;;
    esac
}

test_download_url() {
    local version=$1
    local build
    build=$(get_build_number "$version")
    if [[ "$build" != "unknown" ]]; then
        local package_name="splunkforwarder-${version}-${build}-Linux-x86_64.tgz"
        local nexus_url="http://nexus302:8081/repository/splunk"
        local download_url="${nexus_url}/${package_name}"
        echo "版本 $version -> URL: $download_url"
    else
        echo "版本 $version -> 错误: 未知版本"
    fi
}

# 测试几个版本
test_download_url "9.1.2"
test_download_url "9.1.1" 
test_download_url "9.0.4"
test_download_url "8.2.12"
test_download_url "999.999.999"  # 测试未知版本

echo
echo "3. 测试脚本参数验证:"

# 测试参数验证
echo "测试无参数调用:"
./upgrade_splunk_forwarder.sh 2>/dev/null && echo "  - 意外成功" || echo "  - 正确失败: 需要指定参数"

echo "测试同时指定文件和版本:"
./upgrade_splunk_forwarder.sh -f test.tgz -v 9.1.2 2>/dev/null && echo "  - 意外成功" || echo "  - 正确失败: 参数冲突"

echo "测试无效版本格式:"
./upgrade_splunk_forwarder.sh -v invalid_version 2>/dev/null && echo "  - 意外成功" || echo "  - 正确失败: 版本格式错误"

echo
echo "=== 测试完成 ===" 