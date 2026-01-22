# Infrastructure

CloudFormation templates for deploying the SageMaker vLLM endpoint with OpenAI-compatible API.

## Full Stack Deployment

Deploys everything in one CloudFormation stack:
- SageMaker vLLM endpoint
- API Gateway + Lambda proxy
- EC2 instance (t3.small) with OpenWebUI
- S3 bucket for Lambda deployment artifacts

```bash
./deploy-full-stack.sh --vpc-id vpc-xxx --subnet-id subnet-xxx
```

### Architecture

```
┌─────────────┐     ┌──────────────┐     ┌────────────┐     ┌─────────────────┐
│  OpenWebUI  │────▶│ API Gateway  │────▶│   Lambda   │────▶│ SageMaker vLLM  │
│  (EC2)      │     │ (HTTP API)   │     │  (proxy)   │     │   Endpoint      │
└─────────────┘     └──────────────┘     └────────────┘     └─────────────────┘
     ▲                                                              │
     │                                                              │
     └──────────────── Users access via browser ────────────────────┘
```

### Prerequisites

1. **AWS CLI configured** with credentials
2. **VPC and Subnet IDs** - Need a VPC with a public subnet
3. **GPU quota** - ml.g4dn.xlarge requires quota (check Service Quotas)
4. **uv** - Python package manager for Lambda packaging ([install](https://github.com/astral-sh/uv))

### Find VPC and Subnet

```bash
# List VPCs
aws ec2 describe-vpcs --region eu-north-1 \
  --query 'Vpcs[*].[VpcId,Tags[?Key==`Name`].Value|[0]]' --output table

# List public subnets in a VPC
aws ec2 describe-subnets --region eu-north-1 \
  --filters Name=vpc-id,Values=vpc-xxx \
  --query 'Subnets[?MapPublicIpOnLaunch==`true`].[SubnetId,AvailabilityZone]' --output table
```

### Deploy

```bash
./deploy-full-stack.sh \
  --vpc-id vpc-0123456789abcdef0 \
  --subnet-id subnet-0123456789abcdef0 \
  --key-pair my-key  # Optional, for SSH access
```

**Options:**
| Flag | Description | Default |
|------|-------------|---------|
| `--vpc-id` | VPC ID (required) | - |
| `--subnet-id` | Public subnet ID (required) | - |
| `--stack-name` | CloudFormation stack name | openai-sagemaker-stack |
| `--model-id` | HuggingFace model | distilgpt2 |
| `--key-pair` | EC2 key pair for SSH | - |
| `--region` | AWS region | eu-north-1 |
| `--sagemaker-instance` | SageMaker instance type | ml.g4dn.xlarge |
| `--ec2-instance` | EC2 instance type | t3.small |
| `--lambda-s3-bucket` | S3 bucket for Lambda code | Auto-created |

### Outputs

After deployment:
- **OpenWebUI**: `http://<elastic-ip>` (port 80)
- **API Gateway**: `https://xxx.execute-api.region.amazonaws.com`
- **SageMaker Endpoint**: `<stack-name>-vllm-endpoint`

### Cleanup

```bash
# Delete stack and S3 bucket
./delete-full-stack.sh --stack-name openai-sagemaker-stack

# Keep S3 bucket for faster redeployment
./delete-full-stack.sh --stack-name openai-sagemaker-stack --keep-s3
```

## Cost Estimate

| Resource | Type | Cost |
|----------|------|------|
| SageMaker | ml.g4dn.xlarge | ~$0.74/hour |
| EC2 | t3.small | ~$0.02/hour |
| API Gateway | HTTP API | ~$1/million requests |
| Lambda | 256MB | Free tier likely covers |
| Elastic IP | Attached | Free |

**Total**: ~$0.76/hour (~$550/month if 24/7)

## Files

| File | Description |
|------|-------------|
| `full-stack.yaml` | Complete stack CloudFormation |
| `deploy-full-stack.sh` | Deploy script (packages Lambda, uploads to S3, deploys CF) |
| `delete-full-stack.sh` | Cleanup script (deletes stack and S3 bucket) |
| `../lambda/openai-proxy/` | Lambda function source code |

## Security Notes

⚠️ **Development/Testing Only** - This setup has:
- No API authentication on API Gateway
- OpenWebUI with auth disabled
- SSH open (restricted by CIDR parameter)

For production, add:
- API Gateway authentication (API keys, IAM, Cognito)
- OpenWebUI authentication enabled
- VPC endpoints for SageMaker
- HTTPS with custom domain
