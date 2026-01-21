# SageMaker DistilGPT-2 Endpoint

[![Deploy SageMaker Endpoint](https://github.com/oriolrius/sagemaker-distilgpt2-endpoint/actions/workflows/deploy.yml/badge.svg)](https://github.com/oriolrius/sagemaker-distilgpt2-endpoint/actions/workflows/deploy.yml)

Deploy and test a DistilGPT-2 language model on AWS SageMaker using GitHub Actions CI/CD.

## Features

- Automated deployment pipeline using GitHub Actions
- Downloads model from Hugging Face Hub
- Packages model with custom inference code
- Deploys to AWS SageMaker with PyTorch container
- Automatic endpoint testing after deployment
- Conventional commits with commitizen

## Architecture Overview

```
┌───────────────────┐
│   Hugging Face    │
│       Hub         │
│  (distilgpt2)     │
└─────────┬─────────┘
          │ download model
          ▼
┌───────────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│  GitHub Actions   │     │                  │     │  SageMaker Endpoint │
│  (package model)  │────▶│  S3 Bucket       │────▶│  (ml.m5.large)      │
│                   │     │  model.tar.gz    │     │                     │
└───────────────────┘     └──────────────────┘     └──────────┬──────────┘
                                                              │
          ┌───────────────────────────────────────────────────┘
          ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  AWS PyTorch Inference Container                                        │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────┐ │
│  │ PyTorch 2.0.1   │  │ TorchServe      │  │ Your Code (from S3)    │ │
│  │ Python 3.10     │  │ Model Server    │  │ ├── inference.py       │ │
│  └─────────────────┘  └─────────────────┘  │ └── requirements.txt   │ │
│                                             │     transformers==4.28 │ │
│  Model files (from S3):                     │     safetensors        │ │
│  ├── model.safetensors                      └─────────────────────────┘ │
│  ├── tokenizer.json                                                     │
│  └── config.json                                                        │
└─────────────────────────────────────────────────────────────────────────┘
          │
          ▼
┌───────────────────┐
│  Client Request   │
│  POST /invocations│
│  {"inputs": "..."}│
└───────────────────┘
```

## Project Structure

```
.
├── .github/
│   └── workflows/
│       └── deploy.yml       # GitHub Actions CI/CD workflow
├── .githooks/
│   └── commit-msg           # Conventional commits validation
├── code/
│   ├── inference.py         # SageMaker inference handler
│   └── requirements.txt     # Container dependencies
├── scripts/
│   ├── deploy.py            # Deployment script
│   └── test_endpoint.py     # Endpoint testing script
├── pyproject.toml           # Project configuration
└── README.md
```

## Quick Start

### 1. Set up GitHub Secrets

Add these secrets to your repository (Settings → Secrets → Actions):

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key |
| `AWS_SESSION_TOKEN` | Session token (if using temporary credentials) |

### 2. Trigger Deployment

The workflow triggers automatically on push to `main` when `code/` or `scripts/` change.

Or trigger manually: **Actions** → **Deploy SageMaker Endpoint** → **Run workflow**

### 3. Test the Endpoint

```python
import json
import boto3

runtime = boto3.client('sagemaker-runtime', region_name='eu-north-1')

response = runtime.invoke_endpoint(
    EndpointName='distilgpt2-endpoint-YYYYMMDD-HHMMSS',  # Check AWS console for name
    ContentType='application/json',
    Body=json.dumps({'inputs': 'The future of artificial intelligence'})
)

result = json.loads(response['Body'].read().decode())
print(result['generated_text'])
```

## Container Requirements

The PyTorch SageMaker container does NOT include HuggingFace libraries. The `code/requirements.txt` specifies:

```
transformers==4.28.0
safetensors
```

**Version notes:**
- `transformers==4.28.0` avoids conflicts with the container's pre-installed `huggingface_hub`
- `safetensors` is required for loading models in `.safetensors` format

## Local Development

### Prerequisites

```bash
# Install dependencies
pip install boto3 transformers torch

# Configure AWS credentials
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...
export AWS_REGION=eu-north-1
```

### Deploy Manually

```bash
# Deploy
python scripts/deploy.py

# Wait for endpoint (5-10 minutes)
aws sagemaker wait endpoint-in-service --endpoint-name <endpoint-name>

# Test
python scripts/test_endpoint.py <endpoint-name>
```

### Conventional Commits

This project uses [commitizen](https://commitizen-tools.github.io/commitizen/) for conventional commits:

```bash
# Install dev dependencies
uv sync --group dev

# Interactive commit
uv run cz commit

# Or use standard git commit with conventional format
git commit -m "feat: add new feature"
```

## AWS Resources

### Container Image (eu-north-1)

```
763104351884.dkr.ecr.eu-north-1.amazonaws.com/pytorch-inference:2.0.1-cpu-py310
```

### Model Tarball Structure

```
model.tar.gz
├── config.json
├── generation_config.json
├── model.safetensors
├── tokenizer.json
├── tokenizer_config.json
├── vocab.json
├── merges.txt
├── special_tokens_map.json
└── code/
    ├── inference.py
    └── requirements.txt
```

## Troubleshooting

### CloudWatch Logs

```
https://eu-north-1.console.aws.amazon.com/cloudwatch/home?region=eu-north-1#logEventViewer:group=/aws/sagemaker/Endpoints/<endpoint-name>
```

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `Worker died` | Code crash during model loading | Check CloudWatch logs |
| `ModuleNotFoundError` | Missing dependency | Add to `code/requirements.txt` |
| `Invocation timed out` | Model loading too slow | Use larger instance |
| `pip install failed` | Version conflicts | Pin compatible versions |

## Cost Management

- **Instance cost:** `ml.m5.large` ~$0.115/hour
- **Delete unused endpoints:**
  ```bash
  aws sagemaker delete-endpoint --endpoint-name <name>
  aws sagemaker delete-endpoint-config --endpoint-config-name <name>
  aws sagemaker delete-model --model-name <name>
  ```

## License

MIT
