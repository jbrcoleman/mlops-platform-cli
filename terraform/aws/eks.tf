# EKS Cluster Configuration
# Using the official AWS EKS Terraform module
# https://registry.terraform.io/modules/terraform-aws-modules/eks/aws

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = local.cluster_name
  kubernetes_version = var.eks_version

  # Cluster endpoint access
  endpoint_public_access  = true
  endpoint_private_access = true

  # Cluster encryption (optional)
  encryption_config = var.create_eks_kms_key ? {
    resources        = ["secrets"]
    provider_key_arn = aws_kms_key.eks[0].arn
  } : null

  # VPC Configuration
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Cluster Addons
  # NOTE: With EKS Auto Mode, only VPC CNI should use before_compute = true
  # Auto Mode provisions nodes automatically based on workload requirements
  addons = {
    # VPC CNI must be first - required for pod networking before any compute
    vpc-cni = {
      most_recent                 = true
      before_compute              = true # Critical: Required for networking setup
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
    # Core addons - Auto Mode will provision nodes for these
    kube-proxy = {
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
    coredns = {
      most_recent                 = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
    # AWS EBS CSI Driver for persistent volumes
    aws-ebs-csi-driver = {
      most_recent                 = true
      service_account_role_arn    = module.ebs_csi_irsa.iam_role_arn
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
  }

  # EKS Auto Mode - AWS automatically manages compute infrastructure
  # No need to configure instance types, disk sizes, or scaling
  # AWS automatically provisions optimal compute based on workload requirements
  compute_config = {
    enabled = true
    # Auto Mode will use general-purpose node pools for ML workloads
    # Automatically handles instance selection, scaling, and optimization
    node_pools = ["general-purpose"]
  }

  # Cluster security group rules
  security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  # Node security group rules
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  tags = local.common_tags
}

# EKS Cluster Access Entry for Terraform user
# This grants the Terraform user admin access to the cluster
resource "aws_eks_access_entry" "terraform_user" {
  cluster_name  = module.eks.cluster_name
  principal_arn = data.aws_caller_identity.current.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "terraform_user_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = data.aws_caller_identity.current.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.terraform_user]
}

# KMS Key for EKS cluster encryption (optional)
resource "aws_kms_key" "eks" {
  count = var.create_eks_kms_key ? 1 : 0

  description             = "KMS key for EKS cluster ${local.cluster_name} encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-eks-key"
    }
  )
}

resource "aws_kms_alias" "eks" {
  count = var.create_eks_kms_key ? 1 : 0

  name          = "alias/${local.cluster_name}-eks"
  target_key_id = aws_kms_key.eks[0].key_id
}

# IRSA for EBS CSI Driver
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${local.cluster_name}-ebs-csi-controller"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.common_tags
}

# Kubernetes provider configuration
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name,
      "--region",
      var.aws_region
    ]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        module.eks.cluster_name,
        "--region",
        var.aws_region
      ]
    }
  }
}

# Data source to ensure cluster is ready before creating kubernetes resources
# This prevents the chicken-and-egg problem where kubernetes provider
# tries to connect before addons make the cluster operational
data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_name

  depends_on = [module.eks]
}

data "aws_eks_addon" "vpc_cni" {
  cluster_name = module.eks.cluster_name
  addon_name   = "vpc-cni"

  depends_on = [module.eks]
}

# Create ml-platform namespace
# Wait for VPC CNI addon to be active before creating kubernetes resources
resource "kubernetes_namespace" "ml_platform" {
  metadata {
    name = var.k8s_namespace

    labels = {
      name        = var.k8s_namespace
      environment = var.environment
    }
  }

  depends_on = [
    module.eks,
    data.aws_eks_addon.vpc_cni,
    data.aws_eks_cluster.cluster
  ]
}
