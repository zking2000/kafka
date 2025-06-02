# GCP项目配置
project_id = "coral-pipe-457011-d2"
region     = "europe-west2"

# 集群配置
cluster_name = "kafka-cluster"

# 网络配置
subnet_cidr   = "10.0.0.0/24"
pods_cidr     = "10.1.0.0/16"
services_cidr = "10.2.0.0/16"
master_cidr   = "10.3.0.0/28"

# 节点配置
machine_type     = "e2-standard-4"  # 4 vCPU, 16GB RAM
node_count       = 3                # 每个区域的初始节点数
min_node_count   = 1                # 最小节点数
max_node_count   = 10               # 最大节点数
disk_size_gb     = 100              # 节点磁盘大小
disk_type        = "pd-ssd"         # SSD磁盘类型
preemptible      = false            # 不使用抢占式实例

# 资源标签
labels = {
  environment = "production"
  application = "kafka"
  team        = "platform"
  managed-by  = "terraform"
  cost-center = "engineering"
} 
