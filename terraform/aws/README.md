# MLOps Platform - AWS Infrastructure with Terraform

This Terraform configuration deploys a production-ready MLOps platform on AWS with:
- EKS cluster for Kubernetes orchestration
- RDS PostgreSQL for MLflow metadata storage
- S3 bucket for MLflow artifacts and DVC data
- IAM Roles for Service Accounts (IRSA) for secure AWS access
- MLflow tracking server deployed to EKS

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         AWS Cloud                            │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                    VPC (10.0.0.0/16)                  │  │
│  │                                                        │  │
│  │  ┌─────────────────┐      ┌──────────────────────┐  │  │
│  │  │  Public Subnets │      │   Private Subnets     │  │  │
│  │  │                 │      │                       │  │  │
│  │  │  - NAT Gateway  │      │  - EKS Worker Nodes   │  │  │
│  │  │  - LoadBalancer │◄─────│  - MLflow Pods        │  │  │
│  │  └─────────────────┘      │  - Training Jobs      │  │  │
│  │                            └──────────────────────┘  │  │
│  │                                                        │  │
│  │  ┌─────────────────┐                                  │  │
│  │  │  DB Subnets     │                                  │  │
│  │  │  - RDS Postgres │                                  │  │
│  │  └─────────────────┘                                  │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────┐     ┌────────────┐     ┌──────────────┐ │
│  │  S3 Bucket   │     │    KMS     │     │   Secrets    │ │
│  │  (Artifacts) │     │    Keys    │     │   Manager    │ │
│  └──────────────┘     └────────────┘     └──────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Tools Required
- [Terraform](https://www.terraform.io/downloads) >= 1.6.0
- [AWS CLI](https://aws.amazon.com/cli/) >= 2.0
- [kubectl](https://kubernetes.io/docs/tasks/tools/) >= 1.28
- [eksctl](https://eksctl.io/) (optional, for troubleshooting)

### AWS Permissions
Your AWS credentials must have permissions to create:
- VPC and networking resources
- EKS clusters and node groups
- RDS instances
- S3 buckets
- IAM roles and policies
- KMS keys
- Secrets Manager secrets

## Quick Start

### 1. Configure AWS Credentials

```bash
aws configure
# Enter your AWS Access Key ID, Secret Access Key, and default region
```

### 2. Initialize Terraform

```bash
cd terraform/aws
terraform init
```

### 3. Create Configuration File

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your desired values
```

**Important variables to configure:**
- `aws_region`: Your AWS region
- `project_name`: Unique name for your project
- `owner`: Your email or team identifier
- `environment`: dev, staging, or production

### 4. Review the Plan

```bash
terraform plan
```

This will show you all resources that will be created. Review carefully!

### 5. Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted. This will take approximately **20-25 minutes** to complete.

**What's being created:**
- ✅ VPC with public, private, and database subnets (2 min)
- ✅ NAT Gateway and VPC endpoints (2 min)
- ✅ EKS cluster (15 min)
- ✅ EKS managed node group (5 min)
- ✅ RDS PostgreSQL instance (10 min)
- ✅ S3 bucket with encryption and lifecycle policies (1 min)
- ✅ IAM roles and policies (1 min)
- ✅ MLflow deployment to Kubernetes (2 min)

### 6. Configure kubectl

```bash
aws eks update-kubeconfig --region $(terraform output -raw region) --name $(terraform output -raw cluster_name)
```

### 7. Verify Deployment
2
```bash
# Check EKS nodes
kubectl get nodes

# Check MLflow pods
kubectl get pods -n ml-platform

# Check MLflow service
kubectl get svc -n ml-platform
```

### 8. Access MLflow

#### Option A: Port Forward (Development)
```bash
kubectl port-forward svc/mlflow-server -n ml-platform 5000:5000
```
Then access: http://localhost:5000

#### Option B: LoadBalancer (Production)
```bash
# Get the LoadBalancer URL
kubectl get svc mlflow-server -n ml-platform -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```
Access: http://<loadbalancer-hostname>:5000

### 9. Update MLP CLI Configuration

```bash
# Get the configuration snippet
terraform output mlp_config_snippet

# Update your ~/.mlp/config.yaml with the values
```

## Important Outputs

After deployment, Terraform provides these outputs:

```bash
# View all outputs
terraform output

# Specific outputs
terraform output cluster_name              # EKS cluster name
terraform output s3_artifacts_bucket       # S3 bucket for artifacts
terraform output rds_endpoint              # RDS endpoint
terraform output configure_kubectl_command # Command to configure kubectl
```

## Cost Estimate

Approximate monthly costs for this infrastructure:

| Resource | Configuration | Monthly Cost |
|----------|---------------|--------------|
| EKS Control Plane | 1 cluster | ~$73 |
| EC2 Instances | 2x t3.medium | ~$60 |
| RDS PostgreSQL | db.t3.micro | ~$15 |
| S3 Storage | 100GB + requests | ~$5 |
| Data Transfer | Variable | ~$10 |
| **Total** | | **~$163/month** |

### Cost Optimization Tips

1. **Use smaller instances for dev:**
   ```hcl
   environment = "dev"
   node_instance_types = ["t3.small"]
   rds_instance_class = "db.t3.micro"
   ```

2. **Scale down when not in use:**
   ```bash
   # Scale node group to 0
   aws eks update-nodegroup-config \
     --cluster-name <cluster-name> \
     --nodegroup-name <nodegroup-name> \
     --scaling-config minSize=0,maxSize=4,desiredSize=0
   ```

3. **Use Spot instances for training workloads** (configure in EKS node group)

4. **Enable S3 lifecycle policies** (already configured)

## Configuration Reference

### Required Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region | `us-west-2` |
| `project_name` | Project name | `mlops-platform` |
| `environment` | Environment name | `production` |

### VPC Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` |
| `availability_zones` | AZs to use | First 2 AZs in region |

### EKS Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `eks_version` | Kubernetes version | `1.28` |
| `node_instance_types` | Worker node instance types | `["t3.medium"]` |
| `node_desired_size` | Desired number of nodes | `2` |
| `node_min_size` | Minimum nodes | `2` |
| `node_max_size` | Maximum nodes | `4` |

### RDS Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `rds_instance_class` | RDS instance class | `db.t3.micro` |
| `rds_allocated_storage` | Storage in GB | `20` |
| `rds_engine_version` | PostgreSQL version | `15.4` |
| `rds_backup_retention_period` | Backup retention days | `7` |

## Security Features

### Network Security
- ✅ Private subnets for EKS nodes and RDS
- ✅ Security groups with least-privilege access
- ✅ VPC endpoints for S3 and ECR (no internet access needed)
- ✅ VPC Flow Logs enabled

### Data Security
- ✅ S3 bucket encryption with KMS
- ✅ RDS encryption at rest with KMS
- ✅ EKS secrets encryption with KMS
- ✅ SSL/TLS enforced for all connections
- ✅ RDS credentials in AWS Secrets Manager

### Access Control
- ✅ IAM Roles for Service Accounts (IRSA)
- ✅ Kubernetes RBAC
- ✅ Least-privilege IAM policies
- ✅ No public RDS access

### Monitoring
- ✅ CloudWatch metrics and logs
- ✅ RDS Enhanced Monitoring
- ✅ RDS Performance Insights
- ✅ CloudWatch Alarms for critical metrics

## Troubleshooting

### EKS Cluster Not Accessible

```bash
# Update kubeconfig
aws eks update-kubeconfig --region <region> --name <cluster-name>

# Check cluster status
aws eks describe-cluster --name <cluster-name> --region <region>

# Check nodes
kubectl get nodes
```

### MLflow Pods Not Starting

```bash
# Check pod status
kubectl get pods -n ml-platform

# Check pod logs
kubectl logs -n ml-platform -l app=mlflow-server

# Check events
kubectl get events -n ml-platform --sort-by='.lastTimestamp'
```

### RDS Connection Issues

```bash
# Test connectivity from a pod
kubectl run -it --rm debug --image=postgres:15 --restart=Never -n ml-platform -- \
  psql -h <rds-endpoint> -U mlflowadmin -d mlflow

# Check security groups
aws ec2 describe-security-groups --group-ids <rds-sg-id>
```

### S3 Access Issues

```bash
# Check IRSA role
kubectl get sa mlflow-sa -n ml-platform -o yaml

# Test S3 access from a pod
kubectl run -it --rm debug --image=amazon/aws-cli --restart=Never \
  --serviceaccount=mlflow-sa -n ml-platform -- \
  s3 ls s3://<bucket-name>/
```

## Maintenance

### Updating Kubernetes Version

```bash
# Update variable
# eks_version = "1.29"

# Plan and apply
terraform plan
terraform apply
```

### Scaling Nodes

```bash
# Update variables
# node_desired_size = 3
# node_max_size = 6

terraform apply
```

### Database Backups

Automated backups are enabled with 7-day retention. To take a manual snapshot:

```bash
aws rds create-db-snapshot \
  --db-instance-identifier <instance-id> \
  --db-snapshot-identifier manual-backup-$(date +%Y%m%d)
```

## Cleanup

To destroy all infrastructure:

```bash
# WARNING: This will delete everything including data!
terraform destroy
```

**Note:** S3 bucket must be empty before destruction. To force delete:

```bash
# Empty the bucket first
aws s3 rm s3://<bucket-name> --recursive

# Then destroy
terraform destroy
```

## Advanced Configuration

### Adding GPU Nodes

Add a GPU node group in `eks.tf`:

```hcl
gpu_workers = {
  name = "${local.cluster_name}-gpu-workers"
  instance_types = ["g4dn.xlarge"]
  capacity_type  = "SPOT"  # Cost optimization
  min_size     = 0
  max_size     = 2
  desired_size = 0

  labels = {
    workload = "gpu-training"
  }

  taints = [{
    key    = "nvidia.com/gpu"
    value  = "true"
    effect = "NO_SCHEDULE"
  }]
}
```

### Adding Ingress Controller

```bash
# Install AWS Load Balancer Controller
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"

helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=<cluster-name>
```

### Enabling Cluster Autoscaler

The infrastructure is ready for cluster autoscaler. Install it:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
```

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review Terraform logs: `terraform plan -out=plan.log`
3. Check AWS CloudWatch logs
4. Open an issue in the project repository

## Next Steps

After deploying infrastructure:

1. **Configure MLP CLI** with the outputs
2. **Create your first experiment**: `mlp experiment create my-model`
3. **Run a training job**: `mlp experiment run ./my-model`
4. **View results in MLflow UI**

## References

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [MLflow Documentation](https://mlflow.org/docs/latest/index.html)
