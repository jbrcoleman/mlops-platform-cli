# VPC Module for EKS
# Using the official AWS VPC Terraform module
# https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.cluster_name}-vpc"
  cidr = var.vpc_cidr

  # Use specified AZs or default to first 2 in region
  azs = length(var.availability_zones) > 0 ? var.availability_zones : [
    data.aws_availability_zones.available.names[0],
    data.aws_availability_zones.available.names[1]
  ]

  # Subnet configuration
  # Private subnets: EKS worker nodes, RDS
  # Public subnets: NAT gateways, Load balancers
  private_subnets = [
    cidrsubnet(var.vpc_cidr, 4, 0), # 10.0.0.0/20
    cidrsubnet(var.vpc_cidr, 4, 1), # 10.0.16.0/20
  ]

  public_subnets = [
    cidrsubnet(var.vpc_cidr, 8, 48), # 10.0.48.0/24
    cidrsubnet(var.vpc_cidr, 8, 49), # 10.0.49.0/24
  ]

  database_subnets = [
    cidrsubnet(var.vpc_cidr, 8, 50), # 10.0.50.0/24
    cidrsubnet(var.vpc_cidr, 8, 51), # 10.0.51.0/24
  ]

  # Enable NAT Gateway for private subnet internet access
  enable_nat_gateway   = true
  single_nat_gateway   = var.environment == "dev" ? true : false # Cost optimization for dev
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Enable VPC Flow Logs for security monitoring
  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true

  # Kubernetes-specific tags
  # Required for EKS to identify subnets
  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  database_subnet_tags = {
    Name = "${local.cluster_name}-db"
  }

  tags = local.common_tags
}

# VPC Endpoints for cost optimization and security
# S3 Gateway Endpoint (no charge)
# Note: Explicitly depends on EKS to ensure proper destroy order
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.${var.aws_region}.s3"

  route_table_ids = concat(
    module.vpc.private_route_table_ids,
    module.vpc.public_route_table_ids
  )

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-s3-endpoint"
    }
  )

  # Ensure VPC endpoints are not deleted before EKS cluster
  depends_on = [
    module.eks
  ]
}

# ECR API Endpoint (for pulling container images)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-ecr-api-endpoint"
    }
  )

  # Ensure VPC endpoints are not deleted before EKS cluster
  depends_on = [
    module.eks
  ]
}

# ECR DKR Endpoint (for pulling container images)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-ecr-dkr-endpoint"
    }
  )

  # Ensure VPC endpoints are not deleted before EKS cluster
  depends_on = [
    module.eks
  ]
}

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${local.cluster_name}-vpc-endpoints-"
  description = "Security group for VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-vpc-endpoints-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}
