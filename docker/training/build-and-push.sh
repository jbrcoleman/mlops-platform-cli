#!/bin/bash
# Build and push training images to ECR

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
VERSION="${1:-v1.0.0}"

echo -e "${GREEN}Building and pushing training images${NC}"
echo "Region: $AWS_REGION"
echo "Account: $AWS_ACCOUNT_ID"
echo "Version: $VERSION"
echo ""

# Get cluster name from Terraform
cd ../../terraform/aws
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "mlops-platform-dev")
cd ../../docker/training

echo "Cluster: $CLUSTER_NAME"
echo ""

# ECR repositories
ECR_BASE="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
PYTORCH_REPO="${ECR_BASE}/${CLUSTER_NAME}-training-pytorch"
TENSORFLOW_REPO="${ECR_BASE}/${CLUSTER_NAME}-training-tensorflow"
SKLEARN_REPO="${ECR_BASE}/${CLUSTER_NAME}-training-sklearn"

# Login to ECR
echo -e "${YELLOW}[1/4] Logging in to ECR...${NC}"
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_BASE
echo -e "${GREEN}✓ Logged in${NC}"
echo ""

# Build PyTorch image
echo -e "${YELLOW}[2/4] Building PyTorch image...${NC}"
docker build -f Dockerfile.pytorch -t $PYTORCH_REPO:$VERSION -t $PYTORCH_REPO:latest .
echo -e "${GREEN}✓ PyTorch image built${NC}"
echo ""

# Build TensorFlow image
echo -e "${YELLOW}[3/4] Building TensorFlow image...${NC}"
docker build -f Dockerfile.tensorflow -t $TENSORFLOW_REPO:$VERSION -t $TENSORFLOW_REPO:latest .
echo -e "${GREEN}✓ TensorFlow image built${NC}"
echo ""

# Build scikit-learn image
echo -e "${YELLOW}[4/4] Building scikit-learn image...${NC}"
docker build -f Dockerfile.sklearn -t $SKLEARN_REPO:$VERSION -t $SKLEARN_REPO:latest .
echo -e "${GREEN}✓ scikit-learn image built${NC}"
echo ""

# Push images
echo -e "${YELLOW}Pushing images to ECR...${NC}"
docker push $PYTORCH_REPO:$VERSION
docker push $PYTORCH_REPO:latest
echo -e "${GREEN}✓ PyTorch pushed${NC}"

docker push $TENSORFLOW_REPO:$VERSION
docker push $TENSORFLOW_REPO:latest
echo -e "${GREEN}✓ TensorFlow pushed${NC}"

docker push $SKLEARN_REPO:$VERSION
docker push $SKLEARN_REPO:latest
echo -e "${GREEN}✓ scikit-learn pushed${NC}"

echo ""
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}All images built and pushed successfully!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo ""
echo "PyTorch:    $PYTORCH_REPO:$VERSION"
echo "TensorFlow: $TENSORFLOW_REPO:$VERSION"
echo "Sklearn:    $SKLEARN_REPO:$VERSION"
echo ""
echo "Update your dev.tfvars with these values:"
echo ""
echo "training_image_pytorch    = \"$PYTORCH_REPO:latest\""
echo "training_image_tensorflow = \"$TENSORFLOW_REPO:latest\""
echo "training_image_sklearn    = \"$SKLEARN_REPO:latest\""
