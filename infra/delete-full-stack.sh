#!/bin/bash
# Delete full stack
#
# Usage:
#   ./delete-full-stack.sh [--stack-name name] [--region region]

set -e

STACK_NAME="openai-sagemaker-stack"
REGION="${AWS_REGION:-eu-north-1}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--stack-name name] [--region region]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "============================================"
echo "Deleting Full Stack"
echo "============================================"
echo "Stack Name: $STACK_NAME"
echo "Region:     $REGION"
echo "============================================"
echo ""
echo "This will delete:"
echo "  - SageMaker endpoint, config, and model"
echo "  - API Gateway and Lambda"
echo "  - EC2 instance and Elastic IP"
echo "  - IAM roles"
echo ""
read -p "Are you sure? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Check if stack exists
if ! aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK_NAME" &>/dev/null; then
    echo "Stack '$STACK_NAME' does not exist in $REGION"
    exit 0
fi

echo ""
echo "Deleting CloudFormation stack..."
echo "(This may take several minutes)"

aws cloudformation delete-stack \
    --region "$REGION" \
    --stack-name "$STACK_NAME"

echo "Waiting for stack deletion..."
aws cloudformation wait stack-delete-complete \
    --region "$REGION" \
    --stack-name "$STACK_NAME"

echo ""
echo "============================================"
echo "Stack deleted successfully!"
echo "============================================"
