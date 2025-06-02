terraform {
  required_version = ">= 1.0"
  
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
  
  # 可选：配置远程状态存储
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket"
  #   prefix = "terraform/gke-kafka"
  # }
} 
