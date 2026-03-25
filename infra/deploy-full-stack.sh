#!/bin/bash
# Deploy full stack: SageMaker vLLM + API Gateway + Lambda + OpenWebUI on ECS Fargate
#
# Usage:
#   ./deploy-full-stack.sh [options]
#
# Optional:
#   --stack-name    CloudFormation stack name (default: openai-sagemaker-stack)
#   --model-id      HuggingFace model ID (default: Qwen/Qwen2.5-1.5B-Instruct)
#   --region        AWS region (default: eu-west-1)
#
# Prerequisites:
#   - AWS CLI configured with credentials
#   - uv (Python package manager) installed

set -e

# Defaults
STACK_NAME="openai-sagemaker-stack"
MODEL_ID="Qwen/Qwen2.5-1.5B-Instruct"
REGION="${AWS_REGION:-eu-west-1}"
SAGEMAKER_INSTANCE="ml.g4dn.xlarge"
LAMBDA_S3_BUCKET=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        --model-id)
            MODEL_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --sagemaker-instance)
            SAGEMAKER_INSTANCE="$2"
            shift 2
            ;;
        --lambda-s3-bucket)
            LAMBDA_S3_BUCKET="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --stack-name          Stack name (default: openai-sagemaker-stack)"
            echo "  --model-id            HuggingFace model (default: Qwen/Qwen2.5-1.5B-Instruct)"
            echo "  --region              AWS region (default: eu-west-1)"
            echo "  --sagemaker-instance  SageMaker instance (default: ml.g4dn.xlarge)"
            echo "  --lambda-s3-bucket    S3 bucket for Lambda code (auto-created if not specified)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo "Deploying Full Stack"
echo "============================================"
echo "Stack Name:         $STACK_NAME"
echo "Region:             $REGION"
echo "Model:              $MODEL_ID"
echo "SageMaker Instance: $SAGEMAKER_INSTANCE"
echo "============================================"
echo ""
echo "This will create:"
echo "  - VPC with public subnet and internet gateway"
echo "  - SageMaker endpoint (~7-10 min to start)"
echo "  - API Gateway + Lambda"
echo "  - ECS Fargate service with OpenWebUI"
echo ""
echo "Estimated cost: ~\$0.77/hour (mostly SageMaker GPU)"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

#############################################
# Package Lambda Function
#############################################
echo ""
echo "Packaging Lambda function..."

LAMBDA_DIR="$SCRIPT_DIR/../lambda/openai-proxy"
BUILD_DIR="$SCRIPT_DIR/../.build"
LAMBDA_ZIP="lambda-openai-proxy.zip"
LAMBDA_S3_KEY="lambda/$STACK_NAME/$LAMBDA_ZIP"

# Clean and create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/package"

# Install dependencies using uv (boto3 is included in Lambda runtime, but install anyway for consistency)
echo "Installing Lambda dependencies..."
if command -v uv &> /dev/null; then
    uv pip install --target "$BUILD_DIR/package" boto3 --quiet
else
    pip install --target "$BUILD_DIR/package" boto3 --quiet
fi

# Copy source code
cp -r "$LAMBDA_DIR/src/"* "$BUILD_DIR/package/"

# Create zip file
echo "Creating Lambda deployment package..."
cd "$BUILD_DIR/package"
zip -r "../$LAMBDA_ZIP" . -q
cd "$SCRIPT_DIR"

echo "Lambda package created: $BUILD_DIR/$LAMBDA_ZIP"

#############################################
# Create/Verify S3 Bucket for Lambda
#############################################
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if [ -z "$LAMBDA_S3_BUCKET" ]; then
    LAMBDA_S3_BUCKET="${STACK_NAME}-lambda-${AWS_ACCOUNT_ID}-${REGION}"
fi

echo ""
echo "Using S3 bucket: $LAMBDA_S3_BUCKET"

# Create bucket if it doesn't exist
if ! aws s3api head-bucket --bucket "$LAMBDA_S3_BUCKET" --region "$REGION" 2>/dev/null; then
    echo "Creating S3 bucket for Lambda artifacts..."
    if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket \
            --bucket "$LAMBDA_S3_BUCKET" \
            --region "$REGION"
    else
        aws s3api create-bucket \
            --bucket "$LAMBDA_S3_BUCKET" \
            --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION"
    fi
fi

# Upload Lambda package to S3
echo "Uploading Lambda package to S3..."
aws s3 cp "$BUILD_DIR/$LAMBDA_ZIP" "s3://$LAMBDA_S3_BUCKET/$LAMBDA_S3_KEY" --region "$REGION"

echo "Lambda uploaded to: s3://$LAMBDA_S3_BUCKET/$LAMBDA_S3_KEY"

#############################################
# Build CloudFormation Parameters
#############################################
PARAMS="HuggingFaceModelId=$MODEL_ID"
PARAMS="$PARAMS SageMakerInstanceType=$SAGEMAKER_INSTANCE"
PARAMS="$PARAMS LambdaS3Bucket=$LAMBDA_S3_BUCKET"
PARAMS="$PARAMS LambdaS3Key=$LAMBDA_S3_KEY"

# Deploy stack
echo ""
echo "Deploying CloudFormation stack..."
echo "(This will take ~7-10 minutes for SageMaker endpoint)"
echo ""

aws cloudformation deploy \
    --region "$REGION" \
    --stack-name "$STACK_NAME" \
    --template-file "$SCRIPT_DIR/full-stack.yaml" \
    --parameter-overrides $PARAMS \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset

# Get outputs
echo ""
echo "Getting stack outputs..."

API_ENDPOINT=$(aws cloudformation describe-stacks \
    --region "$REGION" \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='ApiGatewayEndpoint'].OutputValue" \
    --output text)

ENDPOINT_NAME=$(aws cloudformation describe-stacks \
    --region "$REGION" \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='SageMakerEndpointName'].OutputValue" \
    --output text)

ECS_CLUSTER=$(aws cloudformation describe-stacks \
    --region "$REGION" \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='ECSClusterName'].OutputValue" \
    --output text)

ECS_SERVICE=$(aws cloudformation describe-stacks \
    --region "$REGION" \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='ECSServiceName'].OutputValue" \
    --output text)

#############################################
# Discover Fargate Task Public IP
#############################################
echo ""
echo "Waiting for Fargate task to start..."

OPENWEBUI_IP=""
for i in {1..30}; do
    TASK_ARN=$(aws ecs list-tasks \
        --region "$REGION" \
        --cluster "$ECS_CLUSTER" \
        --service-name "$ECS_SERVICE" \
        --query "taskArns[0]" \
        --output text 2>/dev/null || echo "None")

    if [ "$TASK_ARN" != "None" ] && [ -n "$TASK_ARN" ]; then
        ENI_ID=$(aws ecs describe-tasks \
            --region "$REGION" \
            --cluster "$ECS_CLUSTER" \
            --tasks "$TASK_ARN" \
            --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" \
            --output text 2>/dev/null || echo "")

        if [ -n "$ENI_ID" ] && [ "$ENI_ID" != "None" ]; then
            OPENWEBUI_IP=$(aws ec2 describe-network-interfaces \
                --region "$REGION" \
                --network-interface-ids "$ENI_ID" \
                --query "NetworkInterfaces[0].Association.PublicIp" \
                --output text 2>/dev/null || echo "")

            if [ -n "$OPENWEBUI_IP" ] && [ "$OPENWEBUI_IP" != "None" ]; then
                break
            fi
        fi
    fi

    echo "  Attempt $i/30: waiting for task IP..."
    sleep 10
done

echo ""
echo "============================================"
echo "Deployment Complete!"
echo "============================================"
echo ""
echo "SageMaker Endpoint: $ENDPOINT_NAME"
echo "API Gateway:        $API_ENDPOINT"
if [ -n "$OPENWEBUI_IP" ] && [ "$OPENWEBUI_IP" != "None" ]; then
    echo "OpenWebUI:          http://$OPENWEBUI_IP:8080"
else
    echo "OpenWebUI:          (task still starting — check ECS console)"
fi
echo "ECS Cluster:        $ECS_CLUSTER"
echo "ECS Service:        $ECS_SERVICE"
echo ""
echo "============================================"
echo "Test Commands"
echo "============================================"
echo ""
echo "# Test API Gateway:"
echo "curl $API_ENDPOINT/v1/models"
echo ""
echo "# Chat completion:"
echo "curl -X POST $API_ENDPOINT/v1/chat/completions \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"messages\": [{\"role\": \"user\", \"content\": \"The future of AI is\"}], \"max_tokens\": 50}'"
echo ""
if [ -n "$OPENWEBUI_IP" ] && [ "$OPENWEBUI_IP" != "None" ]; then
    echo "# Open WebUI in browser:"
    echo "open http://$OPENWEBUI_IP:8080"
    echo ""
fi
echo "# Get Fargate task IP (if it changes):"
echo "aws ecs list-tasks --cluster $ECS_CLUSTER --service $ECS_SERVICE --query taskArns[0] --output text | \\"
echo "  xargs -I{} aws ecs describe-tasks --cluster $ECS_CLUSTER --tasks {} --query 'tasks[0].attachments[0].details[?name==\`networkInterfaceId\`].value' --output text | \\"
echo "  xargs -I{} aws ec2 describe-network-interfaces --network-interface-ids {} --query NetworkInterfaces[0].Association.PublicIp --output text"
echo ""
echo "============================================"
echo "Cleanup"
echo "============================================"
echo ""
echo "To delete all resources:"
echo "  ./delete-full-stack.sh --stack-name $STACK_NAME --region $REGION"
echo ""
