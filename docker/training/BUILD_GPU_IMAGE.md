# Building GPU-Enabled Docker Images

The GPU-enabled PyTorch image is large (~6GB) and requires sufficient disk space to build.

## Quick Build (Recommended)

The easiest way is to build on an EC2 instance or local machine with Docker:

```bash
# 1. Clone your repository
git clone <your-repo>
cd mlops-platform-cli/docker/training

# 2. Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 296592524620.dkr.ecr.us-east-1.amazonaws.com

# 3. Build and push PyTorch GPU image
docker build -f Dockerfile.pytorch \
  -t 296592524620.dkr.ecr.us-east-1.amazonaws.com/mlops-platform-dev-training-pytorch:latest \
  -t 296592524620.dkr.ecr.us-east-1.amazonaws.com/mlops-platform-dev-training-pytorch:v1.1.0-gpu \
  .

docker push 296592524620.dkr.ecr.us-east-1.amazonaws.com/mlops-platform-dev-training-pytorch:latest
docker push 296592524620.dkr.ecr.us-east-1.amazonaws.com/mlops-platform-dev-training-pytorch:v1.1.0-gpu
```

## Using the Build Script

Alternatively, use the provided build script (requires ~10GB free disk space):

```bash
cd docker/training
./build-and-push.sh v1.1.0-gpu
```

This will build and push all training images (PyTorch, TensorFlow, scikit-learn).

## Build on EC2 (If Local Build Fails)

If you don't have enough local disk space, use an EC2 instance:

```bash
# Launch an EC2 instance (t3.large with 30GB storage recommended)
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t3.large \
  --iam-instance-profile Name=ECRBuildRole \
  --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=30}'

# SSH into the instance
ssh ec2-user@<instance-ip>

# Install Docker
sudo yum update -y
sudo yum install -y docker git
sudo service docker start
sudo usermod -a -G docker ec2-user

# Clone and build
git clone <your-repo>
cd mlops-platform-cli/docker/training
./build-and-push.sh v1.1.0-gpu
```

## What Changed for GPU Support

The updated Dockerfile now uses:

- **Base Image**: `pytorch/pytorch:2.2.1-cuda12.1-cudnn8-runtime` (was `python:3.10-slim`)
- **CUDA Version**: 12.1
- **cuDNN Version**: 8
- **PyTorch**: Pre-installed with GPU support (no need to install separately)

## Verifying the Image

After pushing, verify the image is in ECR:

```bash
aws ecr describe-images \
  --repository-name mlops-platform-dev-training-pytorch \
  --region us-east-1
```

You should see `v1.1.0-gpu` and `latest` tags.

## Testing GPU Support

Once the image is pushed, test it:

```bash
# Run a GPU test job
kubectl run gpu-test --rm -it --restart=Never \
  --image=296592524620.dkr.ecr.us-east-1.amazonaws.com/mlops-platform-dev-training-pytorch:latest \
  --overrides='{"spec":{"tolerations":[{"key":"nvidia.com/gpu","operator":"Exists","effect":"NoSchedule"}],"containers":[{"name":"gpu-test","image":"296592524620.dkr.ecr.us-east-1.amazonaws.com/mlops-platform-dev-training-pytorch:latest","command":["python","-c","import torch; print(f\"CUDA available: {torch.cuda.is_available()}\"); print(f\"GPU count: {torch.cuda.device_count()}\")"],"resources":{"limits":{"nvidia.com/gpu":"1"}}}]}}' \
  -n ml-platform
```

Expected output:
```
CUDA available: True
GPU count: 1
```

## Next Steps

After successfully building and pushing the GPU image:

1. The `latest` tag will automatically be used by new training jobs
2. Rerun your PyTorch test: `mlp experiment run ./test-pytorch`
3. Check logs for "Using device: cuda" instead of "cpu"
4. Monitor GPU utilization in CloudWatch or with `nvidia-smi` in the pod
