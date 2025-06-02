variable "project_id" {
  description = "GCP项目ID"
  type        = string
}

variable "region" {
  description = "GCP区域"
  type        = string
  default     = "europe-west2"
}

variable "cluster_name" {
  description = "GKE集群名称"
  type        = string
  default     = "kafka-cluster"
}

variable "subnet_cidr" {
  description = "子网CIDR范围"
  type        = string
  default     = "10.0.0.0/24"
}

variable "pods_cidr" {
  description = "Pod IP CIDR范围"
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_cidr" {
  description = "Service IP CIDR范围"
  type        = string
  default     = "10.2.0.0/16"
}

variable "master_cidr" {
  description = "GKE主节点CIDR范围"
  type        = string
  default     = "10.3.0.0/28"
}

variable "machine_type" {
  description = "节点机器类型"
  type        = string
  default     = "e2-standard-4"
}

variable "node_count" {
  description = "每个区域的节点数量"
  type        = number
  default     = 1
}

variable "min_node_count" {
  description = "最小节点数量"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "最大节点数量"
  type        = number
  default     = 5
}

variable "disk_size_gb" {
  description = "节点磁盘大小(GB)"
  type        = number
  default     = 100
}

variable "disk_type" {
  description = "节点磁盘类型"
  type        = string
  default     = "pd-ssd"
}

variable "preemptible" {
  description = "是否使用抢占式实例"
  type        = bool
  default     = false
}

variable "labels" {
  description = "资源标签"
  type        = map(string)
  default = {
    environment = "production"
    application = "kafka"
    managed-by  = "terraform"
  }
} 
