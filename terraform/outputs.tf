output "cluster_name" {
  description = "GKE集群名称"
  value       = google_container_cluster.kafka_cluster.name
}

output "cluster_endpoint" {
  description = "GKE集群端点"
  value       = google_container_cluster.kafka_cluster.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "GKE集群CA证书"
  value       = google_container_cluster.kafka_cluster.master_auth.0.cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "GKE集群位置"
  value       = google_container_cluster.kafka_cluster.location
}

output "vpc_network_name" {
  description = "VPC网络名称"
  value       = google_compute_network.kafka_vpc.name
}

output "subnet_name" {
  description = "子网名称"
  value       = google_compute_subnetwork.kafka_subnet.name
}

output "node_service_account" {
  description = "节点服务账号邮箱"
  value       = google_service_account.gke_nodes.email
}

output "cert_manager_service_account" {
  description = "Cert Manager服务账号邮箱"
  value       = google_service_account.cert_manager.email
}

output "kubectl_config_command" {
  description = "配置kubectl的命令"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.kafka_cluster.name} --region ${var.region} --project ${var.project_id}"
}

output "cluster_info" {
  description = "集群信息摘要"
  value = {
    name              = google_container_cluster.kafka_cluster.name
    location          = google_container_cluster.kafka_cluster.location
    node_version      = google_container_cluster.kafka_cluster.node_version
    master_version    = google_container_cluster.kafka_cluster.master_version
    node_count        = var.node_count
    machine_type      = var.machine_type
    disk_size_gb      = var.disk_size_gb
    network           = google_compute_network.kafka_vpc.name
    subnetwork        = google_compute_subnetwork.kafka_subnet.name
  }
}

# DNS相关输出
output "dns_zone_name" {
  description = "私有DNS区域名称"
  value       = google_dns_managed_zone.kafka_private_zone.name
}

output "dns_zone_dns_name" {
  description = "私有DNS区域域名"
  value       = google_dns_managed_zone.kafka_private_zone.dns_name
}

output "kafka_dns_records" {
  description = "Kafka broker DNS记录"
  value = {
    kafka-0 = google_dns_record_set.kafka_0.name
    kafka-1 = google_dns_record_set.kafka_1.name
    kafka-2 = google_dns_record_set.kafka_2.name
  }
}

# HAProxy相关输出
output "haproxy_0_external_ip" {
  description = "HAProxy-0外部IP地址"
  value       = google_compute_address.haproxy_0_external_ip.address
}

output "haproxy_1_external_ip" {
  description = "HAProxy-1外部IP地址"
  value       = google_compute_address.haproxy_1_external_ip.address
}

output "haproxy_2_external_ip" {
  description = "HAProxy-2外部IP地址"
  value       = google_compute_address.haproxy_2_external_ip.address
}

output "haproxy_instances" {
  description = "HAProxy实例信息"
  value = {
    haproxy_0 = {
      name        = google_compute_instance.haproxy_0_vm.name
      zone        = google_compute_instance.haproxy_0_vm.zone
      external_ip = google_compute_address.haproxy_0_external_ip.address
      internal_ip = google_compute_instance.haproxy_0_vm.network_interface.0.network_ip
      kafka_target = "kafka-0"
    }
    haproxy_1 = {
      name        = google_compute_instance.haproxy_1_vm.name
      zone        = google_compute_instance.haproxy_1_vm.zone
      external_ip = google_compute_address.haproxy_1_external_ip.address
      internal_ip = google_compute_instance.haproxy_1_vm.network_interface.0.network_ip
      kafka_target = "kafka-1"
    }
    haproxy_2 = {
      name        = google_compute_instance.haproxy_2_vm.name
      zone        = google_compute_instance.haproxy_2_vm.zone
      external_ip = google_compute_address.haproxy_2_external_ip.address
      internal_ip = google_compute_instance.haproxy_2_vm.network_interface.0.network_ip
      kafka_target = "kafka-2"
    }
  }
}

output "haproxy_service_account" {
  description = "HAProxy服务账号邮箱"
  value       = google_service_account.haproxy_vm.email
}

output "haproxy_ssh_connections" {
  description = "SSH连接到HAProxy VM的命令"
  value = {
    haproxy_0 = "gcloud compute ssh ${google_compute_instance.haproxy_0_vm.name} --zone=${google_compute_instance.haproxy_0_vm.zone} --ssh-flag=\"-p 2234\""
    haproxy_1 = "gcloud compute ssh ${google_compute_instance.haproxy_1_vm.name} --zone=${google_compute_instance.haproxy_1_vm.zone} --ssh-flag=\"-p 2234\""
    haproxy_2 = "gcloud compute ssh ${google_compute_instance.haproxy_2_vm.name} --zone=${google_compute_instance.haproxy_2_vm.zone} --ssh-flag=\"-p 2234\""
  }
}

# 连接信息
output "kafka_external_access" {
  description = "外部访问Kafka的连接信息"
  value = {
    kafka_0_admin_endpoint = "${google_compute_address.haproxy_0_external_ip.address}:9093"
    kafka_1_admin_endpoint = "${google_compute_address.haproxy_1_external_ip.address}:9093"
    kafka_2_admin_endpoint = "${google_compute_address.haproxy_2_external_ip.address}:9093"
    admin_endpoints        = "${google_compute_address.haproxy_0_external_ip.address}:9093,${google_compute_address.haproxy_1_external_ip.address}:9093,${google_compute_address.haproxy_2_external_ip.address}:9093"
    stats_urls = {
      haproxy_0 = "http://${google_compute_address.haproxy_0_external_ip.address}:8080/stats"
      haproxy_1 = "http://${google_compute_address.haproxy_1_external_ip.address}:8080/stats"
      haproxy_2 = "http://${google_compute_address.haproxy_2_external_ip.address}:8080/stats"
    }
  }
}

output "network_configuration" {
  description = "网络配置摘要"
  value = {
    vpc_network           = google_compute_network.kafka_vpc.name
    kafka_subnet         = google_compute_subnetwork.kafka_subnet.name
    kafka_subnet_cidr    = google_compute_subnetwork.kafka_subnet.ip_cidr_range
    haproxy_subnet       = google_compute_subnetwork.haproxy_public_subnet.name
    haproxy_subnet_cidr  = google_compute_subnetwork.haproxy_public_subnet.ip_cidr_range
    dns_zone             = google_dns_managed_zone.kafka_private_zone.dns_name
  }
} 
