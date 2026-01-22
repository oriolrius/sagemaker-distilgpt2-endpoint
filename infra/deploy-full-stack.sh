#!/bin/bash
# Deploy full stack: SageMaker vLLM + API Gateway + Lambda + OpenWebUI on EC2
#
# Usage:
#   ./deploy-full-stack.sh --vpc-id vpc-xxx --subnet-id subnet-xxx [options]
#
# Required:
#   --vpc-id        VPC ID for EC2 instance
#   --subnet-id     Subnet ID for EC2 instance (must be public)
#
# Optional:
#   --stack-name    CloudFormation stack name (default: openai-sagemaker-stack)
#   --model-id      HuggingFace model ID (default: distilgpt2)
#   --key-pair      EC2 Key Pair name for SSH access
#   --region        AWS region (default: eu-north-1)

set -e

# Defaults
STACK_NAME="openai-sagemaker-stack"
MODEL_ID="distilgpt2"
REGION="${AWS_REGION:-eu-north-1}"
SAGEMAKER_INSTANCE="ml.g4dn.xlarge"
EC2_INSTANCE="t3a.small"
KEY_PAIR=""
VPC_ID=""
SUBNET_ID=""

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
        --vpc-id)
            VPC_ID="$2"
            shift 2
            ;;
        --subnet-id)
            SUBNET_ID="$2"
            shift 2
            ;;
        --key-pair)
            KEY_PAIR="$2"
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
        --ec2-instance)
            EC2_INSTANCE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 --vpc-id vpc-xxx --subnet-id subnet-xxx [options]"
            echo ""
            echo "Required:"
            echo "  --vpc-id              VPC ID for EC2 instance"
            echo "  --subnet-id           Subnet ID (must be public subnet)"
            echo ""
            echo "Optional:"
            echo "  --stack-name          Stack name (default: openai-sagemaker-stack)"
            echo "  --model-id            HuggingFace model (default: distilgpt2)"
            echo "  --key-pair            EC2 Key Pair for SSH"
            echo "  --region              AWS region (default: eu-north-1)"
            echo "  --sagemaker-instance  SageMaker instance (default: ml.g4dn.xlarge)"
            echo "  --ec2-instance        EC2 instance (default: t3a.small)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$VPC_ID" ]; then
    echo "ERROR: --vpc-id is required"
    echo ""
    echo "Find your VPC ID with:"
    echo "  aws ec2 describe-vpcs --region $REGION --query 'Vpcs[*].[VpcId,Tags[?Key==\`Name\`].Value|[0]]' --output table"
    exit 1
fi

if [ -z "$SUBNET_ID" ]; then
    echo "ERROR: --subnet-id is required"
    echo ""
    echo "Find public subnets in your VPC with:"
    echo "  aws ec2 describe-subnets --region $REGION --filters Name=vpc-id,Values=$VPC_ID --query 'Subnets[?MapPublicIpOnLaunch==\`true\`].[SubnetId,AvailabilityZone]' --output table"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo "Deploying Full Stack"
echo "============================================"
echo "Stack Name:         $STACK_NAME"
echo "Region:             $REGION"
echo "Model:              $MODEL_ID"
echo "SageMaker Instance: $SAGEMAKER_INSTANCE"
echo "EC2 Instance:       $EC2_INSTANCE"
echo "VPC ID:             $VPC_ID"
echo "Subnet ID:          $SUBNET_ID"
echo "Key Pair:           ${KEY_PAIR:-<none>}"
echo "============================================"
echo ""
echo "This will create:"
echo "  - SageMaker endpoint (~15-20 min to start)"
echo "  - API Gateway + Lambda"
echo "  - EC2 instance with OpenWebUI"
echo ""
echo "Estimated cost: ~\$0.80/hour (mostly SageMaker GPU)"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Build parameters
PARAMS="ParameterKey=HuggingFaceModelId,ParameterValue=$MODEL_ID"
PARAMS="$PARAMS ParameterKey=SageMakerInstanceType,ParameterValue=$SAGEMAKER_INSTANCE"
PARAMS="$PARAMS ParameterKey=EC2InstanceType,ParameterValue=$EC2_INSTANCE"
PARAMS="$PARAMS ParameterKey=VpcId,ParameterValue=$VPC_ID"
PARAMS="$PARAMS ParameterKey=SubnetId,ParameterValue=$SUBNET_ID"

if [ -n "$KEY_PAIR" ]; then
    PARAMS="$PARAMS ParameterKey=EC2KeyPair,ParameterValue=$KEY_PAIR"
fi

# Deploy stack
echo ""
echo "Deploying CloudFormation stack..."
echo "(This will take 15-20 minutes for SageMaker endpoint)"
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

OPENWEBUI_URL=$(aws cloudformation describe-stacks \
    --region "$REGION" \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='OpenWebUIUrl'].OutputValue" \
    --output text)

EC2_IP=$(aws cloudformation describe-stacks \
    --region "$REGION" \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='EC2PublicIP'].OutputValue" \
    --output text)

ENDPOINT_NAME=$(aws cloudformation describe-stacks \
    --region "$REGION" \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='SageMakerEndpointName'].OutputValue" \
    --output text)

echo ""
echo "============================================"
echo "Deployment Complete!"
echo "============================================"
echo ""
echo "SageMaker Endpoint: $ENDPOINT_NAME"
echo "API Gateway:        $API_ENDPOINT"
echo "OpenWebUI:          $OPENWEBUI_URL"
echo "EC2 Public IP:      $EC2_IP"
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
echo "# Open WebUI in browser:"
echo "open $OPENWEBUI_URL"
echo ""
if [ -n "$KEY_PAIR" ]; then
    echo "# SSH to EC2:"
    echo "ssh -i ~/.ssh/$KEY_PAIR.pem ec2-user@$EC2_IP"
    echo ""
fi
echo "============================================"
echo "Cleanup"
echo "============================================"
echo ""
echo "To delete all resources:"
echo "  ./delete-full-stack.sh --stack-name $STACK_NAME --region $REGION"
echo ""
