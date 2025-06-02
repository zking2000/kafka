# Kafka证书验证脚本使用指南

## 概述

`verify-certificates.sh` 是一个全面的Kafka证书验证脚本，包含了之前所有验证方法的完整实现。该脚本可以帮助您验证mTLS证书配置的正确性。

## 功能特点

### 🔍 核心验证功能

1. **证书基本信息验证**
   - 证书格式有效性检查
   - 证书主题和签发者信息
   - 证书有效期检查
   - 证书过期状态检测

2. **证书链验证**
   - 客户端证书链完整性验证
   - 服务器证书链完整性验证
   - CA证书与子证书关系验证

3. **证书指纹验证**
   - CA证书SHA256指纹
   - 客户端证书SHA256指纹
   - 服务器证书SHA256指纹

4. **签发者验证**
   - CA主题与证书签发者匹配检查
   - 证书颁发机构一致性验证

5. **证书用途验证**
   - SSL客户端证书用途检查
   - SSL服务器证书用途检查

6. **私钥匹配验证**
   - 客户端证书与私钥匹配验证
   - 服务器证书与私钥匹配验证

7. **Kubernetes证书验证**
   - K8s Secret中证书与本地证书对比
   - 跨命名空间证书一致性检查

8. **Kafka连接测试**
   - 多端口SSL连接测试
   - 不同Kafka服务端口验证

## 安装要求

### 必需工具
- `openssl` - 证书操作和验证
- `kubectl` - Kubernetes集群访问（可选）

### 系统兼容性
- Linux/macOS bash环境
- Kubernetes集群访问（用于K8s验证）

## 使用方法

### 基本使用

```bash
# 使用默认路径验证所有证书
./verify-certificates.sh

# 查看帮助信息
./verify-certificates.sh --help
```

### 自定义证书路径

```bash
# 指定CA证书路径
./verify-certificates.sh --ca-cert /path/to/ca.crt

# 指定客户端证书和私钥
./verify-certificates.sh \
  --client-cert /path/to/client.crt \
  --client-key /path/to/client.key

# 指定服务器证书和私钥
./verify-certificates.sh \
  --server-cert /path/to/server.crt \
  --server-key /path/to/server.key
```

### 跳过特定验证

```bash
# 跳过Kubernetes证书检查
./verify-certificates.sh --skip-k8s
```

## 默认证书路径

脚本使用以下默认路径：

```
./certs/ca.crt      - CA证书
./certs/client.crt  - 客户端证书
./certs/client.key  - 客户端私钥
./certs/server.crt  - 服务器证书（可选）
./certs/server.key  - 服务器私钥（可选）
```

## 输出解释

### 状态指示符

- ✅ **成功** - 验证通过
- ❌ **失败** - 验证失败
- ⚠️ **警告** - 需要注意的问题

### 颜色编码

- 🟢 **绿色** - 成功状态和最终报告
- 🔴 **红色** - 错误状态
- 🟡 **黄色** - 警告状态
- 🔵 **蓝色** - 信息状态
- 🟣 **紫色** - 验证步骤标题
- 🔷 **青色** - 子步骤标题

## 验证步骤详解

### 1. 工具检查
验证必需的命令行工具是否可用。

### 2. 文件检查
确认所有指定的证书文件存在并可读。

### 3. 证书基本信息
显示每个证书的详细信息：
- 主题(Subject)
- 签发者(Issuer)
- 有效期
- 过期状态

### 4. 证书链验证
验证证书之间的信任关系：
```bash
openssl verify -CAfile ca.crt client.crt
```

### 5. 指纹验证
生成并显示证书的SHA256指纹：
```bash
openssl x509 -in cert.crt -noout -fingerprint -sha256
```

### 6. 签发者验证
比较CA证书主题与子证书签发者：
- CA主题必须与客户端证书签发者匹配
- CA主题必须与服务器证书签发者匹配

### 7. 用途验证
检查证书是否具有正确的用途：
```bash
openssl x509 -in cert.crt -noout -purpose
```

### 8. 私钥匹配验证
验证证书与私钥是否配对：
```bash
# 比较证书和私钥的模数
openssl x509 -in cert.crt -noout -modulus | openssl md5
openssl rsa -in key.key -noout -modulus | openssl md5
```

### 9. Kubernetes证书验证
如果可以访问K8s集群，会检查：
- `kafka` 命名空间中的 `kafka-certs` Secret
- `opentelemetry` 命名空间中的 `kafka-client-certs` Secret
- 本地证书与K8s中证书的指纹对比

### 10. Kafka连接测试
测试不同Kafka端口的SSL连接：
- 9092 - INTERNAL_SSL
- 9093 - EXTERNAL_SSL ⭐
- 9094 - CONTROLLER
- 9095 - KRAFT_API

## 故障排除

### 常见错误

#### 1. 证书格式错误
```
❌ 证书格式无效
```
**解决方案**: 检查证书文件是否为有效的PEM格式。

#### 2. 证书链验证失败
```
❌ 客户端证书链验证失败
```
**解决方案**: 
- 确认CA证书正确
- 检查客户端证书是否由该CA签发

#### 3. 私钥不匹配
```
❌ 客户端证书和私钥不匹配
```
**解决方案**: 确保证书和私钥是配对生成的。

#### 4. 证书已过期
```
❌ 证书已过期
```
**解决方案**: 重新生成有效期内的证书。

#### 5. Kubernetes连接失败
```
警告: 无法连接到Kubernetes集群
```
**解决方案**: 
- 检查kubectl配置
- 确认K8s集群可访问
- 或使用 `--skip-k8s` 跳过K8s验证

### 调试技巧

1. **详细证书信息**:
   ```bash
   openssl x509 -in cert.crt -text -noout
   ```

2. **检查私钥**:
   ```bash
   openssl rsa -in key.key -text -noout
   ```

3. **手动验证连接**:
   ```bash
   openssl s_client -connect kafka:9093 \
     -cert client.crt -key client.key -CAfile ca.crt
   ```

## 示例输出

```bash
=== Kafka证书验证脚本 ===
版本: 1.0

=== 检查必需工具 ===
✅ openssl 已安装
✅ kubectl 已安装

=== 检查证书文件 ===
✅ ./certs/ca.crt 存在
✅ ./certs/client.crt 存在
✅ ./certs/client.key 存在

--- CA证书 基本信息 ---
✅ 证书格式有效
主题: CN=KafkaCA
签发者: CN=KafkaCA
有效期: Jun  1 09:07:57 2025 GMT 到 Jun  1 09:07:57 2026 GMT
✅ 证书未过期

=== 证书链验证 ===
--- 验证客户端证书链 ---
./certs/client.crt: OK
✅ 客户端证书链验证成功

=== 证书指纹验证 ===
--- CA证书指纹 ---
CA证书 SHA256: 2A:3B:4C:5D:6E:7F:...

=== 验证报告 ===
验证时间: 2024-01-15 10:30:45
CA证书: ./certs/ca.crt
客户端证书: ./certs/client.crt
客户端私钥: ./certs/client.key

验证完成！请查看以上结果确认证书配置正确。
```

## 高级用法

### 批量验证多组证书

创建包装脚本来验证多组证书：

```bash
#!/bin/bash
# 验证开发环境证书
./verify-certificates.sh --ca-cert dev/ca.crt --client-cert dev/client.crt

# 验证生产环境证书  
./verify-certificates.sh --ca-cert prod/ca.crt --client-cert prod/client.crt
```

### 集成到CI/CD

在部署管道中使用：

```yaml
# .github/workflows/verify-certs.yml
- name: 验证证书
  run: |
    ./scripts/verify-certificates.sh --skip-k8s
    if [ $? -eq 0 ]; then
      echo "证书验证通过"
    else
      echo "证书验证失败"
      exit 1
    fi
```

## 相关文档

- [KAFKA_PORTS_GUIDE.md](./KAFKA_PORTS_GUIDE.md) - Kafka端口配置指南
- [VERSION_UPGRADE.md](./VERSION_UPGRADE.md) - OpenTelemetry版本升级指南

## 支持和反馈

如果遇到问题或有改进建议，请检查：

1. 证书文件路径是否正确
2. 必需工具是否已安装
3. Kubernetes集群是否可访问（如需要）
4. 文件权限是否正确

## 版本历史

- **v1.0** - 初始版本，包含所有核心验证功能 