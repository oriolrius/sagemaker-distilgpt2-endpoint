# Standalone Deployment

Deploy the full stack as an independent, self-contained environment. This mode creates all required resources including its own SageMaker execution role.

## What Gets Created

| Resource | Description |
|----------|-------------|
| **SageMaker Execution Role** | New IAM role with SageMaker and ECR permissions |
| **SageMaker Model** | vLLM model configuration |
| **SageMaker Endpoint Config** | Endpoint configuration with instance type |
| **SageMaker Endpoint** | Real-time inference endpoint |
| **Lambda Function** | OpenAI API proxy |
| **Lambda Execution Role** | IAM role for Lambda |
| **API Gateway HTTP API** | Public API endpoint |
| **ECS Cluster** | Fargate cluster for OpenWebUI |
| **ECS Service** | Fargate service running OpenWebUI |
| **ECS Task Definition** | Container config (0.5 vCPU / 1 GB) |
| **ECS Security Group** | Network rules for Fargate task |
| **ECS Task Execution Role** | IAM role for pulling images and logging |
| **CloudWatch Log Group** | Logs for Fargate task |

## Prerequisites

1. **AWS CLI** configured with credentials
2. **VPC with public subnet** (MapPublicIpOnLaunch=true)
3. **GPU quota** for ml.g4dn.xlarge (check Service Quotas)
4. **uv** installed for Lambda packaging

## Deploy

```bash
./deploy-full-stack.sh \
  --vpc-id vpc-0123456789abcdef0 \
  --subnet-id subnet-0123456789abcdef0
```

### Optional Parameters

| Flag | Default | Description |
|------|---------|-------------|
| `--stack-name` | openai-sagemaker-stack | CloudFormation stack name |
| `--model-id` | Qwen/Qwen2.5-1.5B-Instruct | HuggingFace model ID |
| `--sagemaker-instance` | ml.g4dn.xlarge | GPU instance type |
| `--region` | eu-west-1 | AWS region |

## When to Use Standalone Mode

- **Quick testing** - No existing SageMaker infrastructure
- **Isolated environments** - Separate from other projects
- **Simple deployments** - No need to share resources
- **Development** - Independent experimentation

## Cleanup

```bash
./delete-full-stack.sh --stack-name openai-sagemaker-stack
```

This deletes all resources including the SageMaker execution role.

## Architecture

```
                     ┌─────────────────────────────────────────────────────────┐
                     │              CloudFormation Stack                       │
                     │                                                         │
┌─────────┐         │  ┌──────────┐    ┌────────┐    ┌─────────────────────┐  │
│ Browser │─────────┼─▶│ OpenWebUI│───▶│  API   │───▶│      Lambda         │  │
└─────────┘         │  │(Fargate) │    │Gateway │    │   (OpenAI Proxy)    │  │
                     │  └──────────┘    └────────┘    └──────────┬──────────┘  │
                     │                                           │             │
                     │                                           ▼             │
                     │                               ┌─────────────────────┐   │
                     │                               │  SageMaker Endpoint │   │
                     │                               │  (vLLM + Qwen2.5)   │   │
                     │                               └─────────────────────┘   │
                     │                                           │             │
                     │                                           ▼             │
                     │                               ┌─────────────────────┐   │
                     │                               │ SageMaker Exec Role │   │
                     │                               │   (created by CF)   │   │
                     │                               └─────────────────────┘   │
                     └─────────────────────────────────────────────────────────┘
```

## See Also

- [INTEGRATED.md](INTEGRATED.md) - Deploy within existing SageMaker Domain
- [README.md](README.md) - Overview and quick start
