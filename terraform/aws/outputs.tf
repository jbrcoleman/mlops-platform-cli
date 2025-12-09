output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the cluster"
  value       = module.eks.cluster_oidc_issuer_url
}

output "region" {
  description = "AWS region"
  value       = var.aws_region
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnets" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

output "s3_artifacts_bucket" {
  description = "S3 bucket name for MLflow artifacts"
  value       = aws_s3_bucket.mlflow_artifacts.id
}

output "s3_artifacts_bucket_arn" {
  description = "S3 bucket ARN for MLflow artifacts"
  value       = aws_s3_bucket.mlflow_artifacts.arn
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.mlflow.endpoint
}

output "rds_database_name" {
  description = "RDS database name"
  value       = aws_db_instance.mlflow.db_name
}

output "rds_master_username" {
  description = "RDS master username"
  value       = aws_db_instance.mlflow.username
  sensitive   = true
}

output "mlflow_service_account_arn" {
  description = "IAM role ARN for MLflow service account"
  value       = module.mlflow_irsa.iam_role_arn
}

output "mlflow_url" {
  description = "MLflow tracking server URL (use kubectl port-forward or create ingress)"
  value       = "Use: kubectl port-forward svc/mlflow-server -n ${var.k8s_namespace} 5000:5000"
}

output "configure_kubectl_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${local.cluster_name}"
}

output "mlp_config_snippet" {
  description = "Configuration snippet for ~/.mlp/config.yaml"
  value = yamlencode({
    kubernetes = {
      context   = module.eks.cluster_arn
      namespace = var.k8s_namespace
    }
    mlflow = {
      tracking_uri  = "http://localhost:5000" # or configure ingress
      artifact_root = "s3://${aws_s3_bucket.mlflow_artifacts.id}/mlflow-artifacts"
    }
    dvc = {
      remote = "s3://${aws_s3_bucket.mlflow_artifacts.id}/dvc-data"
    }
  })
}
