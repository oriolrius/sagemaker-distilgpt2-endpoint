#!/bin/bash
# Generate .env file with API Gateway endpoint URL
#
# Prerequisites:
#   - Deploy the infrastructure first: cd ../infra && ./deploy.sh

set -e

REGION="${AWS_REGION:-eu-north-1}"
STACK_NAME="sagemaker-openai-proxy"

echo "Fetching API Gateway endpoint from CloudFormation..."

# Get API endpoint from CloudFormation stack
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --region "$REGION" \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='ApiEndpoint'].OutputValue" \
    --output text 2>/dev/null)

if [ -z "$API_ENDPOINT" ] || [ "$API_ENDPOINT" == "None" ]; then
    echo "ERROR: Could not find API Gateway endpoint."
    echo "Make sure you've deployed the infrastructure first:"
    echo "  cd ../infra && ./deploy.sh"
    exit 1
fi

echo "Found API endpoint: $API_ENDPOINT"

# Generate .env file
cat > .env << EOF
# API Gateway endpoint (auto-generated on $(date))
OPENAI_API_BASE_URL=${API_ENDPOINT}/v1
EOF

echo "Created .env file"
echo ""
echo "Setup complete! Run:"
echo "  docker compose up -d"
echo ""
echo "Then open: http://localhost:49200"
