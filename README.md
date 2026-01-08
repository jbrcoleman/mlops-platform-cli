# ML Platform CLI (mlp)

A production-ready CLI tool and infrastructure-as-code solution that simplifies MLOps workflows on AWS. Deploy a complete ML platform with experiment tracking, model serving, and GPU support in minutes.

## Features

- **Production-Ready Infrastructure**: Complete AWS setup with Terraform (EKS, RDS, S3, MLflow)
- **Experiment Management**: Scaffold projects and run training jobs on Kubernetes
- **MLflow Integration**: High-availability MLflow server with PostgreSQL backend and S3 artifacts
- **Model Serving**: One-command deployment with REST API endpoints
- **GPU Support**: Automatic GPU node provisioning with Karpenter for PyTorch/TensorFlow
- **Multi-Framework**: Built-in support for PyTorch, TensorFlow, and scikit-learn
- **Cost Optimized**: Auto-scaling infrastructure with spot instance support

## Installation

### From Source (Development)

```bash
# Clone the repository
git clone https://github.com/yourusername/mlops-platform-cli.git
cd mlops-platform-cli

# Install in development mode
pip install -e .
```

### From PyPI (Coming Soon)

```bash
pip install mlp-cli
```

## Quick Start

### 1. Deploy Infrastructure (AWS)

```bash
# Deploy complete ML platform on AWS (EKS, MLflow, RDS, S3)
cd terraform/aws
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your AWS region and preferences
terraform init
terraform apply  # Takes ~20-25 minutes

# Configure kubectl
aws eks update-kubeconfig --region $(terraform output -raw region) --name $(terraform output -raw cluster_name)
```

See [terraform/aws/README.md](terraform/aws/README.md) for detailed infrastructure setup.

### 2. Configure CLI

```bash
# Initialize MLP configuration
mlp init
# Provide: Kubernetes context, namespace (ml-platform), MLflow URI

# Or get config snippet from Terraform
terraform output mlp_config_snippet
```

### 3. Run Your First Experiment

```bash
# Create a new ML project
mlp experiment create my-classifier --framework pytorch

# Run training on Kubernetes
cd my-classifier
mlp experiment run . --gpu 1  # With GPU support

# Check job status
mlp experiment list --status running

# View MLflow experiments
# Open MLflow UI: kubectl port-forward svc/mlflow-server -n ml-platform 5000:5000
```

### 4. Deploy Model

```bash
# Deploy trained model as REST API
mlp model deploy my-classifier --model-uri models:/my-model/1

# List deployments
mlp model list

# Test the endpoint
curl -X POST http://<service-url>/invocations -H 'Content-Type: application/json' -d '{"data": [[...]]}'
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         AWS Cloud                            │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │            EKS Cluster (Auto Mode)                    │  │
│  │                                                        │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌────────────┐ │  │
│  │  │   MLflow     │  │   Training   │  │   Model    │ │  │
│  │  │   Server     │  │   Jobs       │  │   Serving  │ │  │
│  │  │  (2 replicas)│  │  (GPU/CPU)   │  │   (API)    │ │  │
│  │  └──────────────┘  └──────────────┘  └────────────┘ │  │
│  │                                                        │  │
│  │  ┌──────────────────────────────────────────────┐    │  │
│  │  │  Karpenter (Auto-scaling)                     │    │  │
│  │  │  - General NodePool: t3.medium (CPU)         │    │  │
│  │  │  - GPU NodePool: g4dn/g5 (NVIDIA T4/A10G)    │    │  │
│  │  └──────────────────────────────────────────────┘    │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐            │
│  │ RDS        │  │ S3 Bucket  │  │ ECR        │            │
│  │ PostgreSQL │  │ (Artifacts)│  │ (Images)   │            │
│  └────────────┘  └────────────┘  └────────────┘            │
└─────────────────────────────────────────────────────────────┘
```

## Tech Stack

### Infrastructure
- **Cloud Platform:** AWS (EKS, RDS, S3, ECR)
- **Infrastructure as Code:** Terraform
- **Orchestration:** Kubernetes with Karpenter auto-scaling
- **Compute:** EKS Auto Mode with CPU and GPU node pools

### ML Platform
- **CLI Framework:** Python 3.10+ with Click
- **Experiment Tracking:** MLflow 3.7.0 (HA deployment)
- **Model Registry:** MLflow Model Registry
- **Model Serving:** MLflow built-in serving (REST API)
- **Data Storage:** S3 with lifecycle policies and encryption
- **Metadata Store:** PostgreSQL RDS (multi-AZ)

### ML Frameworks
- **PyTorch:** 2.2.1 with CUDA 12.1 and cuDNN 8
- **TensorFlow:** GPU-enabled
- **Scikit-learn:** CPU-optimized

### Development
- **Testing:** pytest
- **Code Quality:** black, mypy
- **Configuration:** Pydantic, YAML

## CLI Commands

### Implemented

- **mlp init** - Initialize configuration (Kubernetes, MLflow, DVC)
- **mlp experiment create** - Scaffold ML projects from templates (simple, pytorch, tensorflow, sklearn)
- **mlp experiment run** - Submit training jobs to Kubernetes with GPU support
- **mlp experiment list** - Monitor running and completed training jobs
- **mlp model deploy** - Deploy models from MLflow registry as REST APIs
- **mlp model list** - List deployed models and their status
- **mlp model delete** - Remove model deployments
- **mlp model logs** - Stream logs from model serving pods

### Planned

- **mlp data** - Data versioning and management (DVC integration)
- **mlp pipeline** - Pipeline orchestration with Argo Workflows
- **mlp monitor** - Model performance monitoring
- **mlp cost** - Infrastructure cost tracking and analysis

## Infrastructure Components

### Fully Implemented

- **EKS Cluster** - Auto Mode with Karpenter for dynamic scaling
- **MLflow Server** - High-availability deployment with 2+ replicas, autoscaling
- **PostgreSQL RDS** - Multi-AZ backend for MLflow metadata
- **S3 Storage** - Encrypted artifact storage with lifecycle policies
- **ECR Repositories** - Three repos for PyTorch, TensorFlow, and scikit-learn images
- **VPC & Networking** - Public/private subnets, NAT gateway, VPC endpoints
- **IAM & Security** - IRSA, KMS encryption, Secrets Manager
- **GPU Support** - Karpenter NodePool for g4dn/g5 instances (configurable)

### Production Features

- Auto-scaling: Karpenter provisions nodes based on demand
- High Availability: MLflow with multiple replicas and Pod Disruption Budgets
- Security: KMS encryption, VPC isolation, IAM roles, no public RDS access
- Monitoring: CloudWatch metrics, RDS Enhanced Monitoring, health checks
- Cost Optimization: Lifecycle policies, spot instance support, automatic cleanup

## GPU Support

The platform provides automatic GPU node provisioning with Karpenter:

- **GPU Instances:** g4dn (NVIDIA T4) and g5 (NVIDIA A10G) families
- **Auto-scaling:** Scales from 0 to save costs, provisions on-demand
- **Docker Images:** PyTorch image with CUDA 12.1 and cuDNN 8
- **Framework Support:** PyTorch and TensorFlow with GPU acceleration
- **Cost Optimization:** Automatic node consolidation and spot instance support

**Usage:**
```bash
# Run training with GPU
mlp experiment run my-model --gpu 1

# GPU nodes are automatically provisioned and torn down
```

See [terraform/aws/GPU_WORKLOADS.md](terraform/aws/GPU_WORKLOADS.md) for detailed configuration.

## Cost Estimate

Approximate monthly costs for the base infrastructure:

| Resource | Configuration | Monthly Cost |
|----------|---------------|--------------|
| EKS Control Plane | 1 cluster | ~$73 |
| EC2 Instances | 2x t3.medium | ~$60 |
| RDS PostgreSQL | db.t3.micro | ~$15 |
| S3 Storage | 100GB | ~$5 |
| Data Transfer | Variable | ~$10 |
| **Base Total** | | **~$163/month** |

**GPU Costs (on-demand, billed per-second when running):**
- g4dn.xlarge (T4): ~$0.526/hour (~$12.60/day if running 24/7)
- g5.xlarge (A10G): ~$1.006/hour (~$24.14/day if running 24/7)

**Typical monthly cost for active development:** $250-400/month (includes periodic GPU usage)

**Cost optimization tips:**
- Use spot instances for GPU workloads (60-70% savings)
- GPU nodes auto-scale to 0 when idle
- S3 lifecycle policies move old artifacts to cheaper storage
- Scale node groups to 0 during non-working hours

## Project Documentation

- [AWS Infrastructure Setup](terraform/aws/README.md) - Complete Terraform deployment guide
- [GPU Workloads Configuration](terraform/aws/GPU_WORKLOADS.md) - GPU setup and usage
- [Building GPU Docker Images](docker/training/BUILD_GPU_IMAGE.md) - Custom image creation
- [MLflow Image Build](terraform/aws/BUILD_MLFLOW_IMAGE.md) - MLflow server customization

## Development

### Setting Up Development Environment

```bash
# Install development dependencies
pip install -r requirements-dev.txt

# Run tests
pytest

# Format code
black mlp/

# Type checking
mypy mlp/
```

### Running Tests

```bash
# Run all tests
pytest tests/

# Run with coverage
pytest tests/ --cov=mlp --cov-report=html

# Run specific test file
pytest tests/test_experiment.py
```

**Test Coverage:**
- Template scaffolding (PyTorch, TensorFlow, scikit-learn)
- Configuration management and validation
- CLI command functionality
- Project name validation

## Key Highlights

- **Production-Grade Infrastructure:** Complete AWS deployment with HA, auto-scaling, and security best practices
- **8 CLI Commands:** Fully functional end-to-end ML workflow from experiment creation to model serving
- **GPU Acceleration:** Automatic GPU node provisioning with CUDA 12.1 for PyTorch/TensorFlow
- **Cost-Optimized:** Auto-scaling infrastructure saves ~70% on GPU costs through on-demand provisioning
- **Multi-Framework:** Built-in support for PyTorch, TensorFlow, and scikit-learn with framework detection
- **MLflow HA:** High-availability MLflow server with PostgreSQL RDS and S3 artifact storage
- **Security:** KMS encryption, VPC isolation, IAM roles, Secrets Manager integration
- **Tested:** Comprehensive test suite covering core functionality

