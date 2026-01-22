#!/bin/bash
# Deploy API Gateway + Lambda infrastructure for SageMaker OpenAI proxy
#
# Usage:
#   ./deploy.sh [endpoint-name]
#
# Example:
#   ./deploy.sh vllm-endpoint-20260122-074720

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
STACK_NAME="sagemaker-openai-proxy"
REGION="${AWS_REGION:-eu-north-1}"
LAMBDA_FUNCTION_NAME="sagemaker-openai-proxy"

# Get endpoint name from argument or find latest
if [ -n "$1" ]; then
    ENDPOINT_NAME="$1"
else
    echo "Finding latest vLLM endpoint in $REGION..."
    ENDPOINT_NAME=$(aws sagemaker list-endpoints \
        --region "$REGION" \
        --sort-by CreationTime \
        --sort-order Descending \
        --query "Endpoints[?contains(EndpointName, 'vllm') && EndpointStatus=='InService'].EndpointName | [0]" \
        --output text 2>/dev/null)

    if [ -z "$ENDPOINT_NAME" ] || [ "$ENDPOINT_NAME" == "None" ]; then
        echo "ERROR: No InService vLLM endpoint found in $REGION"
        echo "Usage: $0 <endpoint-name>"
        exit 1
    fi
fi

echo "============================================"
echo "Deploying SageMaker OpenAI Proxy"
echo "============================================"
echo "Region:    $REGION"
echo "Stack:     $STACK_NAME"
echo "Endpoint:  $ENDPOINT_NAME"
echo "============================================"

# Step 1: Deploy CloudFormation stack
echo ""
echo "Step 1: Deploying CloudFormation stack..."
aws cloudformation deploy \
    --region "$REGION" \
    --stack-name "$STACK_NAME" \
    --template-file "$SCRIPT_DIR/api-gateway-lambda.yaml" \
    --parameter-overrides \
        SageMakerEndpointName="$ENDPOINT_NAME" \
        LambdaFunctionName="$LAMBDA_FUNCTION_NAME" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset

# Step 2: Package Lambda code
echo ""
echo "Step 2: Packaging Lambda code..."
LAMBDA_ZIP="/tmp/lambda_function.zip"
cd "$PROJECT_ROOT/api-gw"
zip -j "$LAMBDA_ZIP" lambda_function.py

# Step 3: Update Lambda function code
echo ""
echo "Step 3: Uploading Lambda code..."
aws lambda update-function-code \
    --region "$REGION" \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --zip-file "fileb://$LAMBDA_ZIP" \
    --output text > /dev/null

# Wait for update to complete
echo "Waiting for Lambda update to complete..."
aws lambda wait function-updated \
    --region "$REGION" \
    --function-name "$LAMBDA_FUNCTION_NAME"

# Step 4: Get outputs
echo ""
echo "Step 4: Getting stack outputs..."
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --region "$REGION" \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='ApiEndpoint'].OutputValue" \
    --output text)

# Cleanup
rm -f "$LAMBDA_ZIP"

echo ""
echo "============================================"
echo "Deployment Complete!"
echo "============================================"
echo ""
echo "API Endpoint: $API_ENDPOINT"
echo ""
echo "Test commands:"
echo ""
echo "# List models"
echo "curl $API_ENDPOINT/v1/models"
echo ""
echo "# Chat completion"
echo "curl -X POST $API_ENDPOINT/v1/chat/completions \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"messages\": [{\"role\": \"user\", \"content\": \"The future of AI is\"}], \"max_tokens\": 50}'"
echo ""
