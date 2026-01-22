# AGENTS.md

This document provides guidance for AI agents (Claude Code, Cursor, Copilot, etc.) working with this codebase.

## Project Overview

**sagemaker-using_model** is a complete AWS deployment stack for running fine-tuned HuggingFace language models on SageMaker with an OpenAI-compatible API and web UI. It provides:

- **SageMaker vLLM Endpoint**: GPU-accelerated language model inference
- **OpenAI-Compatible API**: Lambda-based proxy translating OpenAI format to SageMaker
- **API Gateway**: Public HTTP API endpoint
- **OpenWebUI**: Web-based chat interface on EC2
- **CloudFormation**: Complete infrastructure-as-code deployment

## Architecture

```
┌──────────────┐     ┌─────────────┐     ┌────────────┐     ┌──────────────────┐
│   Browser    │ ──▶ │  OpenWebUI  │ ──▶ │    API     │ ──▶ │     Lambda       │
│              │     │    (EC2)    │     │  Gateway   │     │  (OpenAI Proxy)  │
└──────────────┘     └─────────────┘     └────────────┘     └──────────────────┘
                                                                     │
                                                                     ▼
                                                            ┌──────────────────┐
                                                            │    SageMaker     │
                                                            │  vLLM Endpoint   │
                                                            │ (ml.g4dn.xlarge) │
                                                            └──────────────────┘
```

## Directory Structure

```
sagemaker-using_model/
├── .github/workflows/          # CI/CD automation
│   ├── deploy.yml             # Deploy full stack
│   └── destroy.yml            # Cleanup with confirmation
├── infra/                      # Infrastructure as Code
│   ├── full-stack.yaml        # CloudFormation template
│   ├── deploy-full-stack.sh   # Deployment script
│   ├── delete-full-stack.sh   # Cleanup script
│   └── README.md              # Infrastructure docs
├── lambda/                     # Lambda function
│   └── openai-proxy/          # OpenAI compatibility layer
│       ├── pyproject.toml     # Python project (uv)
│       ├── src/openai_proxy/  # Handler code
│       └── tests/             # Unit tests
├── scripts/                    # Standalone tools
│   ├── pyproject.toml         # Python project (uv)
│   └── src/sagemaker_tools/   # Deploy, test, cleanup scripts
├── openwebui/                  # Web UI configuration
│   ├── docker-compose.yml     # Docker Compose config
│   └── setup.sh               # EC2 setup script
├── pyproject.toml             # Root project (commitizen)
├── README.md                  # Main documentation
└── DEPLOYMENT_NOTES.md        # Step-by-step guide
```

## Key Components

### 1. Lambda OpenAI Proxy (`lambda/openai-proxy/`)
- Translates OpenAI `/v1/chat/completions` requests to SageMaker format
- Handles streaming and non-streaming responses
- Environment variable: `SAGEMAKER_ENDPOINT_NAME`

### 2. CloudFormation Stack (`infra/full-stack.yaml`)
- Creates all AWS resources in single deployment
- Parameters: VPC ID, Subnet ID, SSH key, CIDR ranges
- Resources: SageMaker endpoint, Lambda, API Gateway, EC2, IAM roles

### 3. Standalone Tools (`scripts/`)
- `deploy-vllm`: Deploy SageMaker endpoint
- `test-endpoint`: Test endpoint with sample requests
- `test-api-gateway`: Test API Gateway endpoint
- `cleanup`: Delete all resources

### 4. OpenWebUI (`openwebui/`)
- Docker Compose configuration for web UI
- Setup script for EC2 instance
- Connects to API Gateway endpoint

## Technologies

| Category | Technology |
|----------|-----------|
| Language | Python 3.11+ |
| Package Manager | uv (Astral) |
| Cloud | AWS (SageMaker, Lambda, API Gateway, EC2, S3) |
| Infrastructure | CloudFormation |
| CI/CD | GitHub Actions |
| Testing | pytest, moto (AWS mocking) |
| Code Quality | Ruff |
| ML Runtime | vLLM on SageMaker |

## Conventions and Patterns

### Commit Conventions (Conventional Commits)

This project uses [Commitizen](https://commitizen-tools.github.io/commitizen/) with conventional commits for semantic versioning.

**Format:**
```
type(scope)?: description

[optional body]

[optional footer(s)]
```

**Commit Types & Version Bumps:**

| Type | Version Bump | Example |
|------|--------------|---------|
| `feat` | MINOR | `feat: add streaming support` |
| `fix` | PATCH | `fix: correct Lambda timeout` |
| `feat!` or `fix!` | MAJOR | `feat!: change API response format` |
| `docs`, `style`, `refactor`, `test`, `build`, `ci`, `chore`, `perf` | None | Maintenance |

**Setup:**
```bash
git config core.hooksPath .githooks   # Enable commit validation
uv sync --dev                          # Install commitizen
```

**Usage:**
```bash
git commit -m "feat: add new feature"  # Standard commit (validated by hook)
cz commit                              # Interactive commit
cz bump                                # Bump version based on commits
```

### Code Style
- Use Ruff for linting and formatting
- Follow PEP 8 conventions
- Line length: 120 characters
- Python 3.11+ features allowed

### AWS Patterns
- CloudFormation for all infrastructure
- Lambda with minimal dependencies (boto3 only)
- SageMaker vLLM containers
- API Gateway HTTP API (not REST API)

## AWS Credentials Setup

This project requires AWS credentials for deployment. **Claude Code users** can use built-in skills:

### Available Skills

1. **`/aws-credentials-setup`** - Configures AWS credentials for:
   - Local AWS CLI (`~/.aws/credentials`)
   - GitHub repository secrets (for CI/CD workflows)

2. **`/aws-sandbox-credentials`** - Fetches credentials from AWS Innovation Sandbox:
   - Automates browser-based login with TOTP MFA
   - Extracts access keys, secret keys, and session tokens

### Quick Setup (Claude Code)
```
/aws-credentials-setup
```

## Common Tasks

### Deploy Full Stack
```bash
cd infra/
./deploy-full-stack.sh \
  --vpc-id vpc-xxx \
  --subnet-id subnet-xxx \
  --ssh-key-name my-key
```

### Deploy via GitHub Actions
Trigger `deploy.yml` workflow with inputs:
- `vpc_id`: VPC for deployment
- `subnet_id`: Subnet for EC2/SageMaker
- `instance_type`: SageMaker instance (default: ml.g4dn.xlarge)
- `model_id`: HuggingFace model (default: distilgpt2)

### Test Lambda Locally
```bash
cd lambda/openai-proxy
uv sync --dev
uv run pytest -v
uv run ruff check src/ tests/
```

### Test Deployed Endpoint
```bash
cd scripts/
uv sync
uv run test-endpoint --endpoint-name <name>
uv run test-api-gateway --api-url <url>
```

### Cleanup Resources
```bash
cd infra/
./delete-full-stack.sh --stack-name openai-sagemaker-stack
```

Or trigger `destroy.yml` workflow (requires typing "DESTROY" to confirm).

## Environment Variables

### GitHub Secrets (CI/CD)
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN`
- `AWS_REGION` (default: eu-north-1)

### Lambda Runtime
- `SAGEMAKER_ENDPOINT_NAME`: Name of SageMaker endpoint to invoke

### Deployment Parameters
- `HF_MODEL_ID`: HuggingFace model (default: distilgpt2)
- `INSTANCE_TYPE`: SageMaker instance (default: ml.g4dn.xlarge)

## Cost Considerations

- **SageMaker** (ml.g4dn.xlarge): ~$0.74/hour
- **EC2** (t3.small): ~$0.02/hour
- **Total**: ~$0.76/hour (~$550/month if 24/7)
- **Lambda/API Gateway**: Pay per request (negligible for dev)

**Important**: Always clean up resources when not in use!

## Important Notes for Agents

1. **AWS Credentials**: Use `/aws-credentials-setup` skill to configure credentials (never commit them)
2. **Use uv**: All Python projects use `uv` package manager, not pip
3. **Test locally first**: Run Lambda tests before deploying
4. **CloudFormation only**: Never manually create AWS resources
5. **Cleanup resources**: Use destroy workflow to avoid costs
6. **Credential refresh**: AWS sandbox credentials expire; use `/aws-sandbox-credentials` to refresh
7. **Multi-project structure**: Lambda and scripts have separate pyproject.toml files

## File Modification Guidelines

| File | When to Modify |
|------|----------------|
| `lambda/openai-proxy/src/` | Changing OpenAI proxy logic |
| `infra/full-stack.yaml` | Adding/modifying AWS resources |
| `scripts/src/sagemaker_tools/` | Changing deployment/test tools |
| `openwebui/` | Modifying web UI configuration |
| `.github/workflows/` | Changing CI/CD pipeline |
| Root `pyproject.toml` | Changing commitizen config or version |

## Troubleshooting

### Deployment Fails
1. Check CloudFormation events in AWS Console
2. Verify VPC and subnet IDs are correct
3. Ensure IAM permissions are sufficient
4. Check Lambda build logs in GitHub Actions

### Lambda Timeout
1. Increase timeout in CloudFormation (default: 30s)
2. Check SageMaker endpoint is healthy
3. Review CloudWatch logs for errors

### SageMaker Endpoint Not Responding
1. Check endpoint status in SageMaker console
2. Verify model ID is valid HuggingFace model
3. Check instance type has sufficient resources
4. Review CloudWatch logs

### AWS Credentials Issues
1. **Expired credentials**: Run `/aws-sandbox-credentials` to refresh
2. **Missing credentials**: Run `/aws-credentials-setup` to configure
3. **GitHub Actions failing**: Update repository secrets with valid credentials
4. **Permission denied**: Verify IAM policy allows required actions

### OpenWebUI Not Loading
1. Check EC2 security group allows inbound traffic
2. Verify Docker is running on EC2
3. Check API Gateway URL is configured correctly
4. Review Docker logs: `docker-compose logs`
