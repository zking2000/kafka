#!/usr/bin/env python3
import base64
import subprocess
import json
import os

def get_secret_data(secret_name, namespace, key):
    """从Kubernetes Secret获取数据"""
    cmd = f"kubectl get secret {secret_name} -n {namespace} -o jsonpath='{{.data.{key}}}'"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return result.stdout.strip()

def decode_cert(data):
    """智能解码证书数据"""
    try:
        # 第一次base64解码
        first_decode = base64.b64decode(data).decode('utf-8')
        
        # 检查是否是PEM格式
        if first_decode.startswith('-----BEGIN'):
            return first_decode
        
        # 如果不是PEM格式，尝试第二次解码
        try:
            second_decode = base64.b64decode(first_decode).decode('utf-8')
            return second_decode
        except:
            # 如果第二次解码失败，返回第一次解码的结果（可能是二进制数据）
            return base64.b64decode(data)
    except Exception as e:
        print(f"解码失败: {e}")
        return None

def main():
    print("正在从 GKE 集群导出 Kafka 证书...")
    
    # 创建目录
    os.makedirs('certs/pem', exist_ok=True)
    os.makedirs('certs/jks', exist_ok=True)
    
    # PEM证书列表
    pem_certs = {
        'ca.crt': 'ca\\.crt',
        'client.crt': 'client\\.crt', 
        'client.key': 'client\\.key',
        'server.crt': 'server\\.crt',
        'server.key': 'server\\.key',
        'ca.key': 'ca\\.key'
    }
    
    print("=== 导出 PEM 格式证书 ===")
    for filename, key in pem_certs.items():
        print(f"导出 {key} 到 certs/pem/{filename}")
        data = get_secret_data('kafka-tls-certs', 'confluent-kafka', key)
        decoded = decode_cert(data)
        
        if isinstance(decoded, str):
            with open(f'certs/pem/{filename}', 'w') as f:
                f.write(decoded)
            print(f"✅ {filename} 导出成功 (PEM格式)")
        else:
            with open(f'certs/pem/{filename}', 'wb') as f:
                f.write(decoded)
            print(f"✅ {filename} 导出成功 (二进制格式)")
    
    # JKS证书列表
    jks_certs = {
        'kafka.server.keystore.jks': 'kafka\\.server\\.keystore\\.jks',
        'kafka.server.truststore.jks': 'kafka\\.server\\.truststore\\.jks'
    }
    
    print("\n=== 导出 JKS 格式证书 ===")
    for filename, key in jks_certs.items():
        print(f"导出 {key} 到 certs/jks/{filename}")
        data = get_secret_data('kafka-keystore', 'confluent-kafka', key)
        decoded = base64.b64decode(data)
        
        with open(f'certs/jks/{filename}', 'wb') as f:
            f.write(decoded)
        print(f"✅ {filename} 导出成功")
    
    # 导出密码
    print("\n=== 导出密码 ===")
    passwords = {
        'keystore.password': 'keystore\\.password',
        'truststore.password': 'truststore\\.password', 
        'key.password': 'key\\.password'
    }
    
    for filename, key in passwords.items():
        data = get_secret_data('kafka-keystore', 'confluent-kafka', key)
        password = base64.b64decode(data).decode('utf-8')
        
        with open(f'certs/jks/{filename}', 'w') as f:
            f.write(password)
        print(f"✅ {filename} 导出成功")
    
    print("\n=== 验证证书 ===")
    # 验证PEM证书
    for cert_file in ['ca.crt', 'client.crt', 'server.crt']:
        result = subprocess.run(f"openssl x509 -in certs/pem/{cert_file} -text -noout", 
                              shell=True, capture_output=True)
        if result.returncode == 0:
            print(f"✅ {cert_file} 证书有效")
        else:
            print(f"❌ {cert_file} 证书无效")
    
    # 创建OpenTelemetry Secret
    print("\n=== 创建用于 OpenTelemetry 的 Kubernetes Secret ===")
    cmd = """kubectl create secret generic kafka-client-certs \
  --from-file=ca.crt=certs/pem/ca.crt \
  --from-file=tls.crt=certs/pem/client.crt \
  --from-file=tls.key=certs/pem/client.key \
  --namespace=opentelemetry \
  --dry-run=client -o yaml > kafka-client-certs-from-export.yaml"""
    
    subprocess.run(cmd, shell=True)
    print("✅ Secret 清单已生成: kafka-client-certs-from-export.yaml")
    
    # 显示密码信息
    print("\n=== 密码信息 ===")
    with open('certs/jks/keystore.password', 'r') as f:
        print(f"Keystore 密码: {f.read().strip()}")
    with open('certs/jks/truststore.password', 'r') as f:
        print(f"Truststore 密码: {f.read().strip()}")
    with open('certs/jks/key.password', 'r') as f:
        print(f"Key 密码: {f.read().strip()}")
    
    print("\n=== 证书导出完成 ===")
    print("PEM 证书位于: certs/pem/")
    print("JKS 证书位于: certs/jks/")

if __name__ == "__main__":
    main() 