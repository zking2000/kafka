provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# 启用必要的API
resource "google_project_service" "container_api" {
  service = "container.googleapis.com"
  
  disable_dependent_services = true
  disable_on_destroy         = false
}

resource "google_project_service" "compute_api" {
  service = "compute.googleapis.com"
  
  disable_dependent_services = true
  disable_on_destroy         = false
}

resource "google_project_service" "iam_api" {
  service = "iam.googleapis.com"
  
  disable_dependent_services = true
  disable_on_destroy         = false
}

# 创建VPC网络
resource "google_compute_network" "kafka_vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
  
  depends_on = [google_project_service.compute_api]
}

# 创建子网
resource "google_compute_subnetwork" "kafka_subnet" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.kafka_vpc.id
  
  # 启用私有Google访问
  private_ip_google_access = true
  
  # 配置二级IP范围用于Pod和Service
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }
  
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

# 创建Cloud NAT路由器
resource "google_compute_router" "kafka_router" {
  name    = "${var.cluster_name}-router"
  region  = var.region
  network = google_compute_network.kafka_vpc.id
}

# 创建Cloud NAT
resource "google_compute_router_nat" "kafka_nat" {
  name                               = "${var.cluster_name}-nat"
  router                            = google_compute_router.kafka_router.name
  region                            = var.region
  nat_ip_allocate_option            = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# 创建防火墙规则
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.cluster_name}-allow-internal"
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
  
  source_ranges = [var.subnet_cidr, var.pods_cidr, var.services_cidr]
}

# 创建GKE集群
resource "google_container_cluster" "kafka_cluster" {
  name     = var.cluster_name
  location = var.region
  
  # 移除默认节点池
  remove_default_node_pool = true
  initial_node_count       = 1
  
  # 网络配置
  network    = google_compute_network.kafka_vpc.name
  subnetwork = google_compute_subnetwork.kafka_subnet.name
  
  # IP分配策略
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  
  # 启用网络策略
  network_policy {
    enabled = true
  }
  
  # 启用Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  
  # 启用私有集群
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_cidr
    
    master_global_access_config {
      enabled = true
    }
  }
  
  # 主节点授权网络
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "All networks"
    }
  }
  
  # 启用自动升级和修复
  maintenance_policy {
    daily_maintenance_window {
      start_time = "02:00"
    }
  }
  
  # 集群插件配置
  addons_config {
    http_load_balancing {
      disabled = false
    }
    
    horizontal_pod_autoscaling {
      disabled = false
    }
    
    network_policy_config {
      disabled = false
    }
    
    dns_cache_config {
      enabled = true
    }
  }
  
  # 启用二进制授权
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }
  
  # 启用Shielded Nodes
  enable_shielded_nodes = true
  
  # 资源标签
  resource_labels = var.labels
  
  depends_on = [
    google_project_service.container_api,
    google_project_service.iam_api,
    google_compute_subnetwork.kafka_subnet
  ]
}

# 创建主要节点池
resource "google_container_node_pool" "kafka_nodes" {
  name       = "${var.cluster_name}-nodes"
  location   = var.region
  cluster    = google_container_cluster.kafka_cluster.name
  node_count = var.node_count
  
  # 节点配置
  node_config {
    preemptible  = var.preemptible
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = var.disk_type
    
    # 服务账号
    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    
    # 启用Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    
    # Shielded Instance配置
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    
    # 标签和污点
    labels = var.labels
    
    tags = ["kafka-cluster", "gke-node"]
  }
  
  # 自动扩缩容
  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }
  
  # 节点管理
  management {
    auto_repair  = true
    auto_upgrade = true
  }
  
  # 升级设置
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
  
  depends_on = [google_container_cluster.kafka_cluster]
}

# 创建服务账号用于GKE节点
resource "google_service_account" "gke_nodes" {
  account_id   = "${var.cluster_name}-nodes"
  display_name = "GKE Nodes Service Account for ${var.cluster_name}"
}

# 为节点服务账号分配必要的角色
resource "google_project_iam_member" "gke_nodes_registry" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# 创建Kubernetes服务账号用于cert-manager
resource "google_service_account" "cert_manager" {
  account_id   = "${var.cluster_name}-cert-manager"
  display_name = "Cert Manager Service Account for ${var.cluster_name}"
}

# 为cert-manager分配DNS管理权限
resource "google_project_iam_member" "cert_manager_dns" {
  project = var.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.cert_manager.email}"
}

# 创建Workload Identity绑定
resource "google_service_account_iam_member" "cert_manager_workload_identity" {
  service_account_id = google_service_account.cert_manager.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[cert-manager/cert-manager]"
  
  depends_on = [
    google_container_cluster.kafka_cluster,
    google_service_account.cert_manager
  ]
} 
