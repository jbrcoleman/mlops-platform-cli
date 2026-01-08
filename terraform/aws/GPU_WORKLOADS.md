# GPU Workloads Configuration

This guide explains how GPU support is configured in the MLOps platform.

## Overview

The platform uses **Karpenter** (via EKS Auto Mode) to automatically provision GPU nodes when needed. GPU nodes scale from **0 to save costs** and are only created when GPU workloads are scheduled.

## Architecture

- **GPU NodePool**: `gpu-workloads` - Provisions g4dn/g5 GPU instances
- **General NodePool**: `general-purpose` - Provisions CPU-only instances (c/m/r families)
- **Auto-scaling**: Karpenter automatically adds/removes nodes based on workload demands
- **Cost optimization**: GPU nodes have taints to prevent non-GPU workloads from running on them

## Automatic Setup

The GPU NodePool is defined in `karpenter-gpu.tf` and is **automatically applied** when you run:

```bash
terraform apply
```

No manual steps needed! The GPU NodePool will be ready immediately after terraform deployment.

## Configuring Your Training Jobs for GPU

To run training jobs on GPU nodes, your pods need:

### 1. GPU Resource Request

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
  requests:
    nvidia.com/gpu: 1
```

### 2. GPU Toleration

```yaml
tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
```

### 3. (Optional) Node Selector

While not required, you can add a node selector to ensure scheduling on GPU nodes:

```yaml
nodeSelector:
  workload-type: gpu
```

## Using the MLP CLI

The MLP CLI automatically configures GPU settings when you create experiments with GPU support. No manual configuration needed!

Example:
```bash
mlp experiment create my-gpu-model --gpu
```

The CLI will automatically:
- Set `nvidia.com/gpu: 1` resource requests
- Add appropriate tolerations
- Use the GPU-enabled Docker image

## Docker Images

### GPU-Enabled Images

The platform provides GPU-enabled training images:

- **PyTorch**: `{account}.dkr.ecr.{region}.amazonaws.com/{cluster}-training-pytorch:latest`
  - Base: `pytorch/pytorch:2.2.1-cuda12.1-cudnn8-runtime`
  - Includes: CUDA 12.1, cuDNN 8, PyTorch with GPU support

- **TensorFlow**: `{account}.dkr.ecr.{region}.amazonaws.com/{cluster}-training-tensorflow:latest`
  - Base: TensorFlow GPU image

### Rebuilding Images

To rebuild GPU images after changes:

```bash
cd docker/training
./build-and-push.sh v1.1.0-gpu
```

## GPU Instance Types

The GPU NodePool uses the following instance families:

- **g4dn**: NVIDIA T4 GPUs (most cost-effective, good for inference and training)
  - g4dn.xlarge: 1x T4 (16GB GPU memory)
  - g4dn.2xlarge: 1x T4 (16GB GPU memory)

- **g5**: NVIDIA A10G GPUs (better performance, more expensive)
  - g5.xlarge: 1x A10G (24GB GPU memory)
  - g5.2xlarge: 1x A10G (24GB GPU memory)

### Cost Comparison (us-east-1, approximate)

| Instance Type | GPUs | GPU Memory | CPU | RAM | Price/hour |
|---------------|------|------------|-----|-----|------------|
| g4dn.xlarge   | 1x T4 | 16 GB     | 4   | 16 GB | ~$0.526 |
| g4dn.2xlarge  | 1x T4 | 16 GB     | 8   | 32 GB | ~$0.752 |
| g5.xlarge     | 1x A10G | 24 GB   | 4   | 16 GB | ~$1.006 |
| g5.2xlarge    | 1x A10G | 24 GB   | 8   | 32 GB | ~$1.212 |

## Using Spot Instances for GPU (Cost Savings)

To use Spot instances for GPU workloads (60-70% cost savings), edit `karpenter-gpu.tf`:

```hcl
requirements = [
  {
    key      = "karpenter.sh/capacity-type"
    operator = "In"
    values   = ["spot", "on-demand"]  # Prefer spot, fallback to on-demand
  },
  # ... rest of requirements
]
```

**Note**: Spot instances can be interrupted, so only use for fault-tolerant training jobs with checkpointing.

## Verifying GPU Setup

### Check NodePool Status

```bash
kubectl get nodepools
```

Expected output:
```
NAME              NODECLASS   NODES   READY   AGE
general-purpose   default     2       True    30m
gpu-workloads     default     0       True    30m
```

### Check GPU Nodes (when workload is running)

```bash
kubectl get nodes -o wide
```

Look for nodes with "EKS Auto, Nvidia" in the OS-IMAGE column.

### Test GPU Availability in a Pod

```bash
kubectl run gpu-test --rm -it --restart=Never \
  --image=nvidia/cuda:12.0.0-base-ubuntu22.04 \
  --overrides='{"spec":{"tolerations":[{"key":"nvidia.com/gpu","operator":"Exists","effect":"NoSchedule"}]}}' \
  -- nvidia-smi
```

You should see GPU information printed.

## Troubleshooting

### Pod Stuck in Pending

**Symptom**: Pod shows `0/N nodes available: N Insufficient nvidia.com/gpu`

**Solution**:
1. Verify GPU NodePool exists: `kubectl get nodepools`
2. Check pod has GPU toleration (see "Configuring Your Training Jobs" above)
3. Wait 1-2 minutes for Karpenter to provision a GPU node

### Pod Running but Using CPU

**Symptom**: Training logs show "Using device: cpu" instead of "cuda"

**Possible causes**:
1. **Docker image doesn't have CUDA support**
   - Solution: Use GPU-enabled images (see "Docker Images" section)
   - Rebuild images with GPU support: `cd docker/training && ./build-and-push.sh v1.1.0-gpu`

2. **PyTorch/TensorFlow not detecting GPU**
   - Check NVIDIA drivers in pod: `kubectl exec <pod> -- nvidia-smi`
   - Verify CUDA is available: `kubectl exec <pod> -- python -c "import torch; print(torch.cuda.is_available())"`

### GPU Node Not Scaling Down

**Symptom**: GPU node stays running after job completes

**Expected behavior**: Karpenter should remove empty GPU nodes after 1 minute (consolidateAfter: "1m")

**Check**:
```bash
kubectl describe nodepool gpu-workloads
```

Look for consolidation events.

## Manual GPU NodePool Management

If you need to manually manage the GPU NodePool (rare):

### Delete GPU NodePool
```bash
kubectl delete nodepool gpu-workloads
```

### Recreate GPU NodePool
```bash
kubectl apply -f terraform/aws/gpu-nodepool.yaml
```

### Scale GPU Nodes to Zero (emergency cost control)
```bash
# Cordon all GPU nodes
kubectl cordon -l workload-type=gpu

# Delete GPU nodes
kubectl delete nodes -l workload-type=gpu
```

## Best Practices

1. **Always use GPU-enabled Docker images** for GPU workloads
2. **Enable checkpointing** in training scripts for fault tolerance
3. **Use Spot instances** for non-critical training jobs (60-70% cost savings)
4. **Monitor GPU utilization** in your training code to ensure GPU is actually being used
5. **Set appropriate resource limits** to prevent GPU over-subscription
6. **Clean up failed jobs** to prevent GPU nodes from staying up unnecessarily

## Next Steps

After deploying GPU support:

1. Test GPU availability: Run the nvidia-smi test above
2. Run your first GPU training job: `mlp experiment run ./test-pytorch`
3. Monitor costs in AWS Cost Explorer (filter by instance type: g4dn, g5)
4. Consider switching to Spot instances after validating your setup
