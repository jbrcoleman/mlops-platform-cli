# IAM Roles for Service Accounts (IRSA) Configuration

# IAM Policy for MLflow S3 Access
resource "aws_iam_policy" "mlflow_s3_access" {
  name_prefix = "${local.cluster_name}-mlflow-s3-"
  description = "Policy for MLflow to access S3 artifacts bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:ListBucketMultipartUploads"
        ]
        Resource = aws_s3_bucket.mlflow_artifacts.arn
      },
      {
        Sid    = "ObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ]
        Resource = "${aws_s3_bucket.mlflow_artifacts.arn}/*"
      },
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.s3.arn
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-mlflow-s3-policy"
    }
  )
}

# IRSA Role for MLflow Service Account
module "mlflow_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${local.cluster_name}-mlflow-sa"

  role_policy_arns = {
    s3_access = aws_iam_policy.mlflow_s3_access.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.k8s_namespace}:mlflow-sa"]
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-mlflow-irsa-role"
    }
  )
}

# IAM Policy for Training Jobs S3 Access
resource "aws_iam_policy" "training_s3_access" {
  name_prefix = "${local.cluster_name}-training-s3-"
  description = "Policy for ML training jobs to access S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.mlflow_artifacts.arn
      },
      {
        Sid    = "ReadWriteObjects"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.mlflow_artifacts.arn}/*"
      },
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.s3.arn
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-training-s3-policy"
    }
  )
}

# IRSA Role for Training Jobs
module "training_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${local.cluster_name}-training-jobs"

  role_policy_arns = {
    s3_access = aws_iam_policy.training_s3_access.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.k8s_namespace}:training-sa"]
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-training-irsa-role"
    }
  )
}

# Kubernetes Service Account for MLflow
resource "kubernetes_service_account" "mlflow" {
  metadata {
    name      = "mlflow-sa"
    namespace = kubernetes_namespace.ml_platform.metadata[0].name

    annotations = {
      "eks.amazonaws.com/role-arn" = module.mlflow_irsa.iam_role_arn
    }

    labels = {
      app = "mlflow"
    }
  }

  depends_on = [
    module.mlflow_irsa,
    module.eks
  ]
}

# Kubernetes Service Account for Training Jobs
resource "kubernetes_service_account" "training" {
  metadata {
    name      = "training-sa"
    namespace = kubernetes_namespace.ml_platform.metadata[0].name

    annotations = {
      "eks.amazonaws.com/role-arn" = module.training_irsa.iam_role_arn
    }

    labels = {
      app = "training-jobs"
    }
  }

  depends_on = [
    module.training_irsa,
    module.eks
  ]
}

# IAM Policy for Secrets Manager Access (for RDS credentials)
resource "aws_iam_policy" "secrets_manager_access" {
  name_prefix = "${local.cluster_name}-secrets-"
  description = "Policy to read RDS credentials from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.rds_master_password.arn
      },
      {
        Sid    = "DecryptSecrets"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-secrets-policy"
    }
  )
}

# Attach Secrets Manager policy to MLflow IRSA role
resource "aws_iam_role_policy_attachment" "mlflow_secrets" {
  role       = module.mlflow_irsa.iam_role_name
  policy_arn = aws_iam_policy.secrets_manager_access.arn
}

# Output the service account annotations for reference
output "mlflow_service_account_annotation" {
  description = "Annotation for MLflow service account"
  value       = "eks.amazonaws.com/role-arn: ${module.mlflow_irsa.iam_role_arn}"
}

output "training_service_account_annotation" {
  description = "Annotation for training jobs service account"
  value       = "eks.amazonaws.com/role-arn: ${module.training_irsa.iam_role_arn}"
}
