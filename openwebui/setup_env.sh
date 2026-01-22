#!/bin/bash
# Generate .env file from current AWS credentials

set -e

# Get AWS credentials
echo "Fetching AWS credentials..."

if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    # Try to get from AWS CLI config
    AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id 2>/dev/null || echo "")
    AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key 2>/dev/null || echo "")
    AWS_SESSION_TOKEN=$(aws configure get aws_session_token 2>/dev/null || echo "")
fi

if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo "ERROR: AWS credentials not found."
    echo "Run: aws configure"
    exit 1
fi

# Get region - default to eu-north-1 where our SageMaker endpoints are
AWS_REGION_NAME=${AWS_REGION_NAME:-eu-north-1}

# Find latest vLLM endpoint
echo "Finding latest vLLM endpoint..."
ENDPOINT_NAME=$(aws sagemaker list-endpoints \
    --region "$AWS_REGION_NAME" \
    --sort-by CreationTime \
    --sort-order Descending \
    --query "Endpoints[?contains(EndpointName, 'vllm') && EndpointStatus=='InService'].EndpointName | [0]" \
    --output text 2>/dev/null)

if [ -z "$ENDPOINT_NAME" ] || [ "$ENDPOINT_NAME" == "None" ]; then
    echo "WARNING: No InService vLLM endpoint found. Using default."
    ENDPOINT_NAME="vllm-endpoint-20260122-074720"
fi

echo "Using endpoint: $ENDPOINT_NAME"

# Generate .env file
cat > .env << EOF
# AWS Credentials (auto-generated on $(date))
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN
AWS_REGION_NAME=$AWS_REGION_NAME

# LiteLLM API Key
LITELLM_MASTER_KEY=sk-1234

# SageMaker Endpoint
SAGEMAKER_ENDPOINT_NAME=$ENDPOINT_NAME
EOF

echo "Created .env file"

# Update litellm_config.yaml with current endpoint
sed -i "s|sagemaker_chat/vllm-endpoint-[0-9-]*|sagemaker_chat/$ENDPOINT_NAME|g" litellm_config.yaml
echo "Updated litellm_config.yaml with endpoint: $ENDPOINT_NAME"

echo ""
echo "Setup complete! Run:"
echo "  docker compose up -d"
echo ""
echo "Then open: http://localhost:3000"
