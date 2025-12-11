# ECR Repositories for Training Images
# These store pre-built Docker images with ML dependencies

resource "aws_ecr_repository" "training_pytorch" {
  name                 = "${local.cluster_name}-training-pytorch"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(
    local.common_tags,
    {
      Name      = "${local.cluster_name}-training-pytorch"
      Framework = "pytorch"
    }
  )
}

resource "aws_ecr_repository" "training_tensorflow" {
  name                 = "${local.cluster_name}-training-tensorflow"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(
    local.common_tags,
    {
      Name      = "${local.cluster_name}-training-tensorflow"
      Framework = "tensorflow"
    }
  )
}

resource "aws_ecr_repository" "training_sklearn" {
  name                 = "${local.cluster_name}-training-sklearn"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(
    local.common_tags,
    {
      Name      = "${local.cluster_name}-training-sklearn"
      Framework = "sklearn"
    }
  )
}

# Lifecycle policy to clean up old images
resource "aws_ecr_lifecycle_policy" "training_images" {
  for_each = {
    pytorch    = aws_ecr_repository.training_pytorch.name
    tensorflow = aws_ecr_repository.training_tensorflow.name
    sklearn    = aws_ecr_repository.training_sklearn.name
  }

  repository = each.value

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 5
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Remove untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Outputs
output "ecr_repository_pytorch" {
  description = "ECR repository URL for PyTorch training images"
  value       = aws_ecr_repository.training_pytorch.repository_url
}

output "ecr_repository_tensorflow" {
  description = "ECR repository URL for TensorFlow training images"
  value       = aws_ecr_repository.training_tensorflow.repository_url
}

output "ecr_repository_sklearn" {
  description = "ECR repository URL for scikit-learn training images"
  value       = aws_ecr_repository.training_sklearn.repository_url
}
