# Building Custom MLflow Image

## Why Build a Custom Image?

The official MLflow image (`ghcr.io/mlflow/mlflow`) doesn't include PostgreSQL drivers. Installing them on every container start:
- Wastes 60+ seconds per restart
- No package caching
- Increases costs (longer running time)
- Makes debugging harder

## Build and Push Image

### Option 1: Use Docker Hub (Recommended for Testing)

```bash
# Build the image
docker build -t yourdockerhubusername/mlflow-postgres:3.7.0 -f Dockerfile.mlflow .

# Test locally
docker run -p 5000:5000 \
  -e BACKEND_STORE_URI="sqlite:///mlflow/mlflow.db" \
  -e ARTIFACT_ROOT="./mlartifacts" \
  yourdockerhubusername/mlflow-postgres:3.7.0

# Push to Docker Hub
docker push yourdockerhubusername/mlflow-postgres:3.7.0
```

### Option 2: Use Amazon ECR (Recommended for Production)

```bash
# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="us-east-1"

# Create ECR repository
aws ecr create-repository \
  --repository-name mlflow-postgres \
  --region $AWS_REGION

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build the image
docker build -t mlflow-postgres:3.7.0 -f Dockerfile.mlflow .

# Tag for ECR
docker tag mlflow-postgres:3.7.0 \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/mlflow-postgres:3.7.0

# Push to ECR
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/mlflow-postgres:3.7.0
```

### Option 3: Public ECR (No Authentication Required)

```bash
# Build
docker build -t mlflow-postgres:3.7.0 -f Dockerfile.mlflow .

# Tag for public ECR
docker tag mlflow-postgres:3.7.0 public.ecr.aws/YOUR_ALIAS/mlflow-postgres:3.7.0

# Push
docker push public.ecr.aws/YOUR_ALIAS/mlflow-postgres:3.7.0
```

## Update Terraform Configuration

After building and pushing your image, update `dev.tfvars`:

```hcl
# Use your custom image instead of python:3.10-slim
mlflow_image = "yourdockerhubusername/mlflow-postgres:3.7.0"

# Or for ECR:
mlflow_image = "296592524620.dkr.ecr.us-east-1.amazonaws.com/mlflow-postgres:3.7.0"
```

Then update `mlflow.tf` to remove the pip install command:

```hcl
command = ["mlflow", "server"]

args = [
  "--host", "0.0.0.0",
  "--port", "5000",
  "--backend-store-uri", "postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME",
  "--default-artifact-root", "s3://bucket-name/mlflow-artifacts",
  "--serve-artifacts",
  "--gunicorn-opts", "--workers=2 --timeout=120"
]
```

## Benefits of Custom Image

✅ **Fast startup** (~5 seconds vs ~60 seconds)
✅ **No restart loops** - stable container
✅ **Reliable health checks** - readiness probe succeeds
✅ **Production-ready** - proper image versioning
✅ **Cost savings** - less CPU time wasted on installs

## Quick Fix for Current Deployment

For now, to get the current deployment working:

1. **Increase readiness probe delay** to give time for pip install:
   ```yaml
   readinessProbe:
     initialDelaySeconds: 90  # Was 45
   ```

2. **Increase liveness probe delay**:
   ```yaml
   livenessProbe:
     initialDelaySeconds: 120  # Was 60
   ```

3. **Increase memory** if hitting OOM:
   ```hcl
   mlflow_memory_limit = "768Mi"  # Was 512Mi
   ```

But the **proper fix** is to build a custom image as described above!
