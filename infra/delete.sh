#!/bin/bash
# Delete API Gateway + Lambda infrastructure
#
# Usage:
#   ./delete.sh

set -e

STACK_NAME="sagemaker-openai-proxy"
REGION="${AWS_REGION:-eu-north-1}"

echo "============================================"
echo "Deleting SageMaker OpenAI Proxy Stack"
echo "============================================"
echo "Region: $REGION"
echo "Stack:  $STACK_NAME"
echo "============================================"

# Check if stack exists
if ! aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK_NAME" &>/dev/null; then
    echo "Stack '$STACK_NAME' does not exist in $REGION"
    exit 0
fi

# Delete stack
echo ""
echo "Deleting CloudFormation stack..."
aws cloudformation delete-stack \
    --region "$REGION" \
    --stack-name "$STACK_NAME"

echo "Waiting for stack deletion..."
aws cloudformation wait stack-delete-complete \
    --region "$REGION" \
    --stack-name "$STACK_NAME"

echo ""
echo "Stack deleted successfully!"
