variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name, used for resource naming"
  type        = string
  default     = "mlops-platform"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, production)"
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Owner email or identifier"
  type        = string
  default     = "mlops-team"
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones (defaults to first 2 in region)"
  type        = list(string)
  default     = []
}

# EKS Configuration
# Note: Using EKS Auto Mode - compute infrastructure is automatically managed by AWS
# No need for node instance types, sizes, or disk configuration
variable "eks_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.34"
}

variable "create_eks_kms_key" {
  description = "Create KMS key for EKS cluster encryption. Set to false to avoid KMS costs and orphaned keys."
  type        = bool
  default     = false
}

# RDS Configuration
variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "Allocated storage for RDS in GB"
  type        = number
  default     = 20
}

variable "rds_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15" # AWS will use latest minor version (e.g., 15.7, 15.8)
}

variable "rds_database_name" {
  description = "Name of the MLflow database"
  type        = string
  default     = "mlflow"
}

variable "rds_master_username" {
  description = "Master username for RDS"
  type        = string
  default     = "mlflowadmin"
}

variable "rds_backup_retention_period" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}

# MLflow Configuration
variable "mlflow_image" {
  description = "MLflow Docker image"
  type        = string
  default     = "python:3.10-slim" # Will install MLflow with PostgreSQL support
}

variable "mlflow_replicas" {
  description = "Number of MLflow server replicas"
  type        = number
  default     = 2
}

variable "mlflow_cpu_request" {
  description = "CPU request for MLflow pods"
  type        = string
  default     = "500m"
}

variable "mlflow_cpu_limit" {
  description = "CPU limit for MLflow pods"
  type        = string
  default     = "1000m"
}

variable "mlflow_memory_request" {
  description = "Memory request for MLflow pods"
  type        = string
  default     = "512Mi"
}

variable "mlflow_memory_limit" {
  description = "Memory limit for MLflow pods"
  type        = string
  default     = "1Gi"
}

# S3 Configuration
variable "s3_artifact_lifecycle_days" {
  description = "Number of days before artifacts are deleted"
  type        = number
  default     = 90
}

variable "enable_s3_versioning" {
  description = "Enable versioning for S3 bucket"
  type        = bool
  default     = true
}

# Kubernetes Namespace
variable "k8s_namespace" {
  description = "Kubernetes namespace for ML platform"
  type        = string
  default     = "ml-platform"
}

# Security
variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access RDS (defaults to VPC CIDR)"
  type        = list(string)
  default     = []
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for RDS"
  type        = bool
  default     = false
}

# Domain Configuration
variable "domain_name" {
  description = "Domain name for MLflow (e.g., democloud.click)"
  type        = string
  default     = ""
}

variable "mlflow_subdomain" {
  description = "Subdomain for MLflow (e.g., mlflow will create mlflow.democloud.click)"
  type        = string
  default     = "mlflow"
}

# Training Image Configuration
variable "training_image_pytorch" {
  description = "Docker image for PyTorch training jobs (uses ECR if available)"
  type        = string
  default     = "python:3.10-slim" # Fallback to base image
}

variable "training_image_tensorflow" {
  description = "Docker image for TensorFlow training jobs (uses ECR if available)"
  type        = string
  default     = "python:3.10-slim"
}

variable "training_image_sklearn" {
  description = "Docker image for scikit-learn training jobs (uses ECR if available)"
  type        = string
  default     = "python:3.10-slim"
}
