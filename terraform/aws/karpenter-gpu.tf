# # Karpenter GPU NodePool Configuration
# # This creates a dedicated node pool for GPU workloads
# # Automatically applied when terraform is deployed

# resource "kubernetes_manifest" "gpu_nodepool" {
#   manifest = {
#     apiVersion = "karpenter.sh/v1"
#     kind       = "NodePool"
#     metadata = {
#       name = "gpu-workloads"
#       labels = {
#         "app.kubernetes.io/managed-by" = "terraform"
#       }
#     }
#     spec = {
#       # Disruption settings - allows Karpenter to optimize costs
#       disruption = {
#         consolidationPolicy = "WhenEmptyOrUnderutilized"
#         consolidateAfter    = "1m"
#         budgets = [
#           {
#             nodes = "10%"
#           }
#         ]
#       }

#       template = {
#         metadata = {
#           labels = {
#             workload-type = "gpu"
#           }
#         }
#         spec = {
#           # Expire nodes after 7 days to ensure fresh instances
#           expireAfter = "168h"

#           # Use the default EKS Auto Mode NodeClass
#           nodeClassRef = {
#             group = "eks.amazonaws.com"
#             kind  = "NodeClass"
#             name  = "default"
#           }

#           # Requirements for GPU instances
#           requirements = [
#             {
#               key      = "karpenter.sh/capacity-type"
#               operator = "In"
#               values   = ["on-demand"]
#             },
#             {
#               key      = "eks.amazonaws.com/instance-category"
#               operator = "In"
#               values   = ["g"] # G4dn, G5 instances (most cost-effective)
#             },
#             {
#               key      = "eks.amazonaws.com/instance-generation"
#               operator = "Gt"
#               values   = ["3"]
#             },
#             {
#               key      = "kubernetes.io/arch"
#               operator = "In"
#               values   = ["amd64"]
#             },
#             {
#               key      = "kubernetes.io/os"
#               operator = "In"
#               values   = ["linux"]
#             }
#           ]

#           # Taints to ensure only GPU workloads run on these expensive nodes
#           taints = [
#             {
#               key    = "nvidia.com/gpu"
#               value  = "true"
#               effect = "NoSchedule"
#             }
#           ]

#           # Graceful termination period
#           terminationGracePeriod = "1h"
#         }
#       }
#     }
#   }

#   # Ensure this is created after the EKS cluster and VPC CNI addon are ready
#   depends_on = [
#     module.eks,
#     data.aws_eks_addon.vpc_cni,
#     kubernetes_namespace.ml_platform
#   ]
# }

# # Output the GPU NodePool name for reference
# output "gpu_nodepool_name" {
#   description = "Name of the GPU NodePool for Karpenter"
#   value       = kubernetes_manifest.gpu_nodepool.manifest.metadata.name
# }
