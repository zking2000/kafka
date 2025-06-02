# DNS和HAProxy配置文件
# 用于Kafka集群的外部访问

# 启用DNS API
resource "google_project_service" "dns_api" {
  service = "dns.googleapis.com"
  
  disable_dependent_services = true
  disable_on_destroy         = false
}

# 创建Cloud DNS private zone
resource "google_dns_managed_zone" "kafka_private_zone" {
  name     = "${var.cluster_name}-private-zone"
  dns_name = "kafka.internal.cloud."
  
  description = "Private DNS zone for Kafka cluster"
  
  visibility = "private"
  
  private_visibility_config {
    networks {
      network_url = google_compute_network.kafka_vpc.id
    }
  }
  
  depends_on = [google_project_service.dns_api]
}

# 创建Kafka broker DNS A记录
resource "google_dns_record_set" "kafka_0" {
  name = "kafka-0.kafka.internal.cloud."
  type = "A"
  ttl  = 300
  
  managed_zone = google_dns_managed_zone.kafka_private_zone.name
  
  rrdatas = ["10.0.0.36"]  # 实际LoadBalancer内部IP
}

resource "google_dns_record_set" "kafka_1" {
  name = "kafka-1.kafka.internal.cloud."
  type = "A"
  ttl  = 300
  
  managed_zone = google_dns_managed_zone.kafka_private_zone.name
  
  rrdatas = ["10.0.0.37"]  # 实际LoadBalancer内部IP
}

resource "google_dns_record_set" "kafka_2" {
  name = "kafka-2.kafka.internal.cloud."
  type = "A"
  ttl  = 300
  
  managed_zone = google_dns_managed_zone.kafka_private_zone.name
  
  rrdatas = ["10.0.0.38"]  # 实际LoadBalancer内部IP
}

# 创建公共子网用于HAProxy
resource "google_compute_subnetwork" "haproxy_public_subnet" {
  name          = "${var.cluster_name}-haproxy-public-subnet"
  ip_cidr_range = "10.4.0.0/24"
  region        = var.region
  network       = google_compute_network.kafka_vpc.id
  
  # 启用私有Google访问以便安装软件包
  private_ip_google_access = true
}

# 为HAProxy VM创建服务账号
resource "google_service_account" "haproxy_vm" {
  account_id   = "${var.cluster_name}-haproxy"
  display_name = "HAProxy VM Service Account for ${var.cluster_name}"
}

# 为HAProxy分配必要的权限
resource "google_project_iam_member" "haproxy_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.haproxy_vm.email}"
}

resource "google_project_iam_member" "haproxy_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.haproxy_vm.email}"
}

# 创建HAProxy VM启动脚本
locals {
  # HAProxy-0启动脚本 - 只代理kafka-0的9093端口
  haproxy_0_startup_script = <<-EOF
#!/bin/bash
apt-get update
apt-get install -y haproxy dnsutils telnet

# 修改SSH端口到2234
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sed -i '/^Port /d' /etc/ssh/sshd_config
sed -i '/^#Port /d' /etc/ssh/sshd_config
echo "Port 2234" >> /etc/ssh/sshd_config
systemctl restart sshd

# 创建HAProxy配置
cat > /etc/haproxy/haproxy.cfg << 'HAPROXY_CONFIG'
global
    daemon
    log stdout local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy

defaults
    mode tcp
    log global
    option tcplog
    option dontlognull
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

# Kafka-0 Admin Frontend (外部访问9093端口)
frontend kafka_0_admin_frontend
    bind *:9093
    default_backend kafka_0_admin_backend

# Kafka-0 Admin Backend (连接kafka-0:9093)
backend kafka_0_admin_backend
    server kafka-0 kafka-0.kafka.internal.cloud:9093 check

# HAProxy Stats页面
frontend stats
    bind *:8080
    mode http
    stats enable
    stats uri /stats
    stats refresh 30s
    stats admin if TRUE

HAPROXY_CONFIG

# 启动HAProxy
systemctl enable haproxy
systemctl restart haproxy

# 停用UFW防火墙
ufw --force disable

# 配置终端环境
echo "export TERM=xterm-256color" >> ~/.bashrc

# 创建Kafka KRaft模式健康检查脚本
cat > /usr/local/bin/kafka-kraft-health-check.sh << 'HEALTH_CHECK'
#!/bin/bash
# Kafka KRaft模式集群健康检查脚本
echo "=== Kafka KRaft Health Check $(date) ==="

broker="kafka-0.kafka.internal.cloud"

# 检查管理端口 (9093)
if timeout 5 bash -c "</dev/tcp/$broker/9093"; then
    echo "✅ kafka-0 admin port (9093): HEALTHY"
else
    echo "❌ kafka-0 admin port (9093): UNHEALTHY"
fi

echo "=== HAProxy External Endpoints ==="
if timeout 5 bash -c "</dev/tcp/localhost/9093"; then
    echo "✅ External port 9093: HEALTHY"
else
    echo "❌ External port 9093: UNHEALTHY"
fi
HEALTH_CHECK

chmod +x /usr/local/bin/kafka-kraft-health-check.sh

# 设置定期KRaft健康检查
echo "*/5 * * * * root /usr/local/bin/kafka-kraft-health-check.sh >> /var/log/kafka-kraft-health.log 2>&1" >> /etc/crontab

# 创建KRaft配置验证脚本
cat > /usr/local/bin/kafka-kraft-verify.sh << 'VERIFY_SCRIPT'
#!/bin/bash
# KRaft模式配置验证脚本
echo "=== Kafka KRaft Configuration Verification ==="
echo "Date: $(date)"
echo ""

echo "🔍 DNS Resolution Test:"
broker="kafka-0.kafka.internal.cloud"
if nslookup $broker >/dev/null 2>&1; then
    echo "✅ $broker DNS resolution: OK"
else
    echo "❌ $broker DNS resolution: FAILED"
fi

echo ""
echo "🔍 HAProxy Backend Status:"
echo "Check HAProxy stats at: http://$(curl -s ifconfig.me):8080/stats"
echo ""

echo "🔍 HAProxy-0 Ports Summary:"
echo "- Admin/Internal (9093): Used for inter-broker communication"
echo "- External Access: 9093→kafka-0"
VERIFY_SCRIPT

chmod +x /usr/local/bin/kafka-kraft-verify.sh
EOF

  # HAProxy-1启动脚本 - 只代理kafka-1的9093端口
  haproxy_1_startup_script = <<-EOF
#!/bin/bash
apt-get update
apt-get install -y haproxy dnsutils telnet

# 修改SSH端口到2234
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sed -i '/^Port /d' /etc/ssh/sshd_config
sed -i '/^#Port /d' /etc/ssh/sshd_config
echo "Port 2234" >> /etc/ssh/sshd_config
systemctl restart sshd

# 创建HAProxy配置
cat > /etc/haproxy/haproxy.cfg << 'HAPROXY_CONFIG'
global
    daemon
    log stdout local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy

defaults
    mode tcp
    log global
    option tcplog
    option dontlognull
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

# Kafka-1 Admin Frontend (外部访问9093端口)
frontend kafka_1_admin_frontend
    bind *:9093
    default_backend kafka_1_admin_backend

# Kafka-1 Admin Backend (连接kafka-1:9093)
backend kafka_1_admin_backend
    server kafka-1 kafka-1.kafka.internal.cloud:9093 check

# HAProxy Stats页面
frontend stats
    bind *:8080
    mode http
    stats enable
    stats uri /stats
    stats refresh 30s
    stats admin if TRUE

HAPROXY_CONFIG

# 启动HAProxy
systemctl enable haproxy
systemctl restart haproxy

# 停用UFW防火墙
ufw --force disable

# 配置终端环境
echo "export TERM=xterm-256color" >> ~/.bashrc

# 创建Kafka健康检查脚本
cat > /usr/local/bin/kafka-health-check.sh << 'HEALTH_CHECK'
#!/bin/bash
echo "=== Kafka-1 Health Check $(date) ==="

broker="kafka-1.kafka.internal.cloud"

# 检查管理端口 (9093)
if timeout 5 bash -c "</dev/tcp/$broker/9093"; then
    echo "✅ kafka-1 admin port (9093): HEALTHY"
else
    echo "❌ kafka-1 admin port (9093): UNHEALTHY"
fi

echo "=== HAProxy External Endpoints ==="
if timeout 5 bash -c "</dev/tcp/localhost/9093"; then
    echo "✅ External port 9093: HEALTHY"
else
    echo "❌ External port 9093: UNHEALTHY"
fi
HEALTH_CHECK

chmod +x /usr/local/bin/kafka-health-check.sh

# 设置定期健康检查
echo "*/5 * * * * root /usr/local/bin/kafka-health-check.sh >> /var/log/kafka-health.log 2>&1" >> /etc/crontab

# 创建验证脚本
cat > /usr/local/bin/kafka-verify.sh << 'VERIFY_SCRIPT'
#!/bin/bash
echo "=== Kafka-1 Configuration Verification ==="
echo "Date: $(date)"
echo ""

echo "🔍 DNS Resolution Test:"
broker="kafka-1.kafka.internal.cloud"
if nslookup $broker >/dev/null 2>&1; then
    echo "✅ $broker DNS resolution: OK"
else
    echo "❌ $broker DNS resolution: FAILED"
fi

echo ""
echo "🔍 HAProxy Backend Status:"
echo "Check HAProxy stats at: http://$(curl -s ifconfig.me):8080/stats"
echo ""

echo "🔍 HAProxy-1 Ports Summary:"
echo "- Admin/Internal (9093): Used for inter-broker communication"
echo "- External Access: 9093→kafka-1"
VERIFY_SCRIPT

chmod +x /usr/local/bin/kafka-verify.sh
EOF

  # HAProxy-2启动脚本 - 只代理kafka-2的9093端口
  haproxy_2_startup_script = <<-EOF
#!/bin/bash
apt-get update
apt-get install -y haproxy dnsutils telnet

# 修改SSH端口到2234
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sed -i '/^Port /d' /etc/ssh/sshd_config
sed -i '/^#Port /d' /etc/ssh/sshd_config
echo "Port 2234" >> /etc/ssh/sshd_config
systemctl restart sshd

# 创建HAProxy配置
cat > /etc/haproxy/haproxy.cfg << 'HAPROXY_CONFIG'
global
    daemon
    log stdout local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy

defaults
    mode tcp
    log global
    option tcplog
    option dontlognull
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

# Kafka-2 Admin Frontend (外部访问9093端口)
frontend kafka_2_admin_frontend
    bind *:9093
    default_backend kafka_2_admin_backend

# Kafka-2 Admin Backend (连接kafka-2:9093)
backend kafka_2_admin_backend
    server kafka-2 kafka-2.kafka.internal.cloud:9093 check

# HAProxy Stats页面
frontend stats
    bind *:8080
    mode http
    stats enable
    stats uri /stats
    stats refresh 30s
    stats admin if TRUE

HAPROXY_CONFIG

# 启动HAProxy
systemctl enable haproxy
systemctl restart haproxy

# 停用UFW防火墙
ufw --force disable

# 配置终端环境
echo "export TERM=xterm-256color" >> ~/.bashrc

# 创建Kafka健康检查脚本
cat > /usr/local/bin/kafka-health-check.sh << 'HEALTH_CHECK'
#!/bin/bash
echo "=== Kafka-2 Health Check $(date) ==="

broker="kafka-2.kafka.internal.cloud"

# 检查管理端口 (9093)
if timeout 5 bash -c "</dev/tcp/$broker/9093"; then
    echo "✅ kafka-2 admin port (9093): HEALTHY"
else
    echo "❌ kafka-2 admin port (9093): UNHEALTHY"
fi

echo "=== HAProxy External Endpoints ==="
if timeout 5 bash -c "</dev/tcp/localhost/9093"; then
    echo "✅ External port 9093: HEALTHY"
else
    echo "❌ External port 9093: UNHEALTHY"
fi
HEALTH_CHECK

chmod +x /usr/local/bin/kafka-health-check.sh

# 设置定期健康检查
echo "*/5 * * * * root /usr/local/bin/kafka-health-check.sh >> /var/log/kafka-health.log 2>&1" >> /etc/crontab

# 创建验证脚本
cat > /usr/local/bin/kafka-verify.sh << 'VERIFY_SCRIPT'
#!/bin/bash
echo "=== Kafka-2 Configuration Verification ==="
echo "Date: $(date)"
echo ""

echo "🔍 DNS Resolution Test:"
broker="kafka-2.kafka.internal.cloud"
if nslookup $broker >/dev/null 2>&1; then
    echo "✅ $broker DNS resolution: OK"
else
    echo "❌ $broker DNS resolution: FAILED"
fi

echo ""
echo "🔍 HAProxy Backend Status:"
echo "Check HAProxy stats at: http://$(curl -s ifconfig.me):8080/stats"
echo ""

echo "🔍 HAProxy-2 Ports Summary:"
echo "- Admin/Internal (9093): Used for inter-broker communication"
echo "- External Access: 9093→kafka-2"
VERIFY_SCRIPT

chmod +x /usr/local/bin/kafka-verify.sh
EOF
}

# 创建3个静态外部IP地址，分别对应每个HAProxy实例
resource "google_compute_address" "haproxy_0_external_ip" {
  name   = "${var.cluster_name}-haproxy-0-external-ip"
  region = var.region
}

resource "google_compute_address" "haproxy_1_external_ip" {
  name   = "${var.cluster_name}-haproxy-1-external-ip"
  region = var.region
}

resource "google_compute_address" "haproxy_2_external_ip" {
  name   = "${var.cluster_name}-haproxy-2-external-ip"
  region = var.region
}

# 创建HAProxy-0 VM实例 (代理kafka-0:9093)
resource "google_compute_instance" "haproxy_0_vm" {
  name         = "${var.cluster_name}-haproxy-0"
  machine_type = "e2-medium"
  zone         = "${var.region}-a"
  
  tags = ["haproxy", "kafka-proxy", "haproxy-0"]
  
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
      size  = 20
      type  = "pd-standard"
    }
  }
  
  network_interface {
    network    = google_compute_network.kafka_vpc.name
    subnetwork = google_compute_subnetwork.haproxy_public_subnet.name
    
    access_config {
      nat_ip = google_compute_address.haproxy_0_external_ip.address
    }
  }
  
  service_account {
    email  = google_service_account.haproxy_vm.email
    scopes = ["cloud-platform"]
  }
  
  metadata_startup_script = local.haproxy_0_startup_script
  
  metadata = {
    enable-oslogin = "TRUE"
    ssh-keys = "stephenzhou:ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7lBLPrpZQ2/3vHYo1bp8srdbBBtmOsfZd6VVKZIQK09lR0GcczpAyaxGGK9XFVieaV8L/+q9semwfxzGsspIcfNO8lHY41af6GQ6Dz+71rM9h9baLEQJsfdf1hHuR4LOl4EvPFhOOGA9wNYp5wVJ7MNHmH8qNxQDXze7PXdJqVR8FPPdbE+c5E35qm7/1APtodCMRCI4OzMrdGte6oVsupQQQswE8704qbW5OyHjJd2rlvUtgPPpJ097xxqDjG/iQFYjG4kUlCq0rTyx+IePL0ItbvT86MRfJlRwWB0hrveGf0NT8V8ARyeI2DGAuN5+al3xESTsG6yLmlSlwa3LJZ85rgyciDeFRcp1Teq58sbfgUVAJguGNDCiMuKsx5LluEcE4ECniXsHk4yPcZTlNu8uS7SrvxtLhJIQOHyBFtdwfhkZ8y9IG2Nyg9uBRAwhEY99KJIcb7xKnxR0adDdA+G+t+r1gHYeubLftNJ+46Onw2Ok4WadOP877JhbU+r8= stephenzhou@192.168.1.9"
  }
  
  depends_on = [
    google_compute_subnetwork.kafka_subnet,
    google_compute_subnetwork.haproxy_public_subnet,
    google_service_account.haproxy_vm,
    google_dns_managed_zone.kafka_private_zone
  ]
}

# 创建HAProxy-1 VM实例 (代理kafka-1:9093)
resource "google_compute_instance" "haproxy_1_vm" {
  name         = "${var.cluster_name}-haproxy-1"
  machine_type = "e2-medium"
  zone         = "${var.region}-b"
  
  tags = ["haproxy", "kafka-proxy", "haproxy-1"]
  
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
      size  = 20
      type  = "pd-standard"
    }
  }
  
  network_interface {
    network    = google_compute_network.kafka_vpc.name
    subnetwork = google_compute_subnetwork.haproxy_public_subnet.name
    
    access_config {
      nat_ip = google_compute_address.haproxy_1_external_ip.address
    }
  }
  
  service_account {
    email  = google_service_account.haproxy_vm.email
    scopes = ["cloud-platform"]
  }
  
  metadata_startup_script = local.haproxy_1_startup_script
  
  metadata = {
    enable-oslogin = "TRUE"
    ssh-keys = "stephenzhou:ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7lBLPrpZQ2/3vHYo1bp8srdbBBtmOsfZd6VVKZIQK09lR0GcczpAyaxGGK9XFVieaV8L/+q9semwfxzGsspIcfNO8lHY41af6GQ6Dz+71rM9h9baLEQJsfdf1hHuR4LOl4EvPFhOOGA9wNYp5wVJ7MNHmH8qNxQDXze7PXdJqVR8FPPdbE+c5E35qm7/1APtodCMRCI4OzMrdGte6oVsupQQQswE8704qbW5OyHjJd2rlvUtgPPpJ097xxqDjG/iQFYjG4kUlCq0rTyx+IePL0ItbvT86MRfJlRwWB0hrveGf0NT8V8ARyeI2DGAuN5+al3xESTsG6yLmlSlwa3LJZ85rgyciDeFRcp1Teq58sbfgUVAJguGNDCiMuKsx5LluEcE4ECniXsHk4yPcZTlNu8uS7SrvxtLhJIQOHyBFtdwfhkZ8y9IG2Nyg9uBRAwhEY99KJIcb7xKnxR0adDdA+G+t+r1gHYeubLftNJ+46Onw2Ok4WadOP877JhbU+r8= stephenzhou@192.168.1.9"
  }
  
  depends_on = [
    google_compute_subnetwork.kafka_subnet,
    google_compute_subnetwork.haproxy_public_subnet,
    google_service_account.haproxy_vm,
    google_dns_managed_zone.kafka_private_zone
  ]
}

# 创建HAProxy-2 VM实例 (代理kafka-2:9093)
resource "google_compute_instance" "haproxy_2_vm" {
  name         = "${var.cluster_name}-haproxy-2"
  machine_type = "e2-medium"
  zone         = "${var.region}-c"
  
  tags = ["haproxy", "kafka-proxy", "haproxy-2"]
  
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
      size  = 20
      type  = "pd-standard"
    }
  }
  
  network_interface {
    network    = google_compute_network.kafka_vpc.name
    subnetwork = google_compute_subnetwork.haproxy_public_subnet.name
    
    access_config {
      nat_ip = google_compute_address.haproxy_2_external_ip.address
    }
  }
  
  service_account {
    email  = google_service_account.haproxy_vm.email
    scopes = ["cloud-platform"]
  }
  
  metadata_startup_script = local.haproxy_2_startup_script
  
  metadata = {
    enable-oslogin = "TRUE"
    ssh-keys = "stephenzhou:ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7lBLPrpZQ2/3vHYo1bp8srdbBBtmOsfZd6VVKZIQK09lR0GcczpAyaxGGK9XFVieaV8L/+q9semwfxzGsspIcfNO8lHY41af6GQ6Dz+71rM9h9baLEQJsfdf1hHuR4LOl4EvPFhOOGA9wNYp5wVJ7MNHmH8qNxQDXze7PXdJqVR8FPPdbE+c5E35qm7/1APtodCMRCI4OzMrdGte6oVsupQQQswE8704qbW5OyHjJd2rlvUtgPPpJ097xxqDjG/iQFYjG4kUlCq0rTyx+IePL0ItbvT86MRfJlRwWB0hrveGf0NT8V8ARyeI2DGAuN5+al3xESTsG6yLmlSlwa3LJZ85rgyciDeFRcp1Teq58sbfgUVAJguGNDCiMuKsx5LluEcE4ECniXsHk4yPcZTlNu8uS7SrvxtLhJIQOHyBFtdwfhkZ8y9IG2Nyg9uBRAwhEY99KJIcb7xKnxR0adDdA+G+t+r1gHYeubLftNJ+46Onw2Ok4WadOP877JhbU+r8= stephenzhou@192.168.1.9"
  }
  
  depends_on = [
    google_compute_subnetwork.kafka_subnet,
    google_compute_subnetwork.haproxy_public_subnet,
    google_service_account.haproxy_vm,
    google_dns_managed_zone.kafka_private_zone
  ]
}

# 创建防火墙规则允许外部访问HAProxy
resource "google_compute_firewall" "allow_haproxy_external" {
  name    = "${var.cluster_name}-allow-haproxy-external"
  network = google_compute_network.kafka_vpc.name
  
  allow {
    protocol = "tcp"
    ports    = ["9093", "8080"]  # Kafka Admin端口和Stats端口
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["haproxy"]
}

# 创建防火墙规则允许SSH访问HAProxy VM
resource "google_compute_firewall" "allow_ssh_haproxy" {
  name    = "${var.cluster_name}-allow-ssh-haproxy"
  network = google_compute_network.kafka_vpc.name
  
  allow {
    protocol = "tcp"
    ports    = ["2234"]  # 自定义SSH端口
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["haproxy"]
  
  description = "Allow SSH access to HAProxy VM on custom port 2234"
}

# 创建防火墙规则允许HAProxy访问Kafka内部网络
resource "google_compute_firewall" "allow_haproxy_to_kafka" {
  name    = "${var.cluster_name}-allow-haproxy-to-kafka"
  network = google_compute_network.kafka_vpc.name
  
  allow {
    protocol = "tcp"
    ports    = ["9093"]  # Kafka管理端口
  }
  
  # 允许HAProxy子网访问Kafka子网
  source_ranges = ["10.4.0.0/24"]  # HAProxy子网
  target_tags   = ["kafka-cluster", "gke-node"]  # Kafka集群标签
}

# 创建防火墙规则允许内部网络间的通用通信
resource "google_compute_firewall" "allow_internal_haproxy" {
  name    = "${var.cluster_name}-allow-internal-haproxy"
  network = google_compute_network.kafka_vpc.name
  
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  
  allow {
    protocol = "icmp"
  }
  
  source_ranges = ["10.4.0.0/24"]  # HAProxy子网
  target_tags   = ["kafka-cluster", "gke-node"]  # Kafka集群标签
} 
