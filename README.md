# SageMaker DistilGPT-2 Endpoint

Deploy and test a DistilGPT-2 language model on AWS SageMaker using GitHub Actions.

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

### Data Flow

1. **Hugging Face Hub** → Download pre-trained DistilGPT-2 model
2. **GitHub Actions** → Package model + inference code into `model.tar.gz`
3. **S3 Bucket** → Store model artifacts
4. **SageMaker Endpoint** → Deploy using PyTorch container
5. **Container** → Installs requirements.txt, loads model, serves predictions

## Project Structure

```
.
├── .github/
│   └── workflows/
│       └── deploy.yml       # GitHub Actions workflow
├── code/
│   ├── inference.py         # SageMaker inference handler
│   └── requirements.txt     # Container dependencies
├── scripts/
│   ├── deploy.py            # Deployment script
│   └── test_endpoint.py     # Endpoint testing script
├── pyproject.toml
└── README.md
```

## Quick Start

### 1. Set up GitHub Secrets

Add these secrets to your repository:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN` (if using temporary credentials)

### 2. Push to main branch

The workflow triggers automatically on push to `main` when `code/` or `scripts/` change.

Or trigger manually via GitHub Actions → Run workflow.

### 3. Test the endpoint

```python
import json
import boto3

runtime = boto3.client('sagemaker-runtime', region_name='eu-north-1')

response = runtime.invoke_endpoint(
    EndpointName='distilgpt2-endpoint-YYYYMMDD-HHMMSS',  # Replace with actual name
    ContentType='application/json',
    Body=json.dumps({'inputs': 'The future of artificial intelligence'})
)

result = json.loads(response['Body'].read().decode())
print(result['generated_text'])
```

## Requirements

The PyTorch SageMaker container does NOT include HuggingFace libraries. The `code/requirements.txt` specifies:

```
transformers==4.28.0
safetensors
```

**Important version notes:**
- Use `transformers==4.28.0` to avoid conflicts with the container's pre-installed `huggingface_hub`
- Include `safetensors` because models are saved in `.safetensors` format

## Model Tarball Structure

The deployment script creates a `model.tar.gz` with this structure:

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

## Local Development

### Deploy manually

```bash
# Install dependencies
pip install boto3 sagemaker transformers

# Configure AWS credentials
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...
export AWS_REGION=eu-north-1

# Deploy
python scripts/deploy.py

# Wait for endpoint
aws sagemaker wait endpoint-in-service --endpoint-name <endpoint-name>

# Test
python scripts/test_endpoint.py <endpoint-name>
```

## Container Reference

**PyTorch Inference Container (eu-north-1):**
```
763104351884.dkr.ecr.eu-north-1.amazonaws.com/pytorch-inference:2.0.1-cpu-py310
```

**Pre-installed:**
- PyTorch 2.0.1
- Python 3.10
- TorchServe 0.8.2

**NOT pre-installed (add to requirements.txt):**
- transformers
- safetensors

## Troubleshooting

### Check CloudWatch Logs
```
https://eu-north-1.console.aws.amazon.com/cloudwatch/home?region=eu-north-1#logEventViewer:group=/aws/sagemaker/Endpoints/<endpoint-name>
```

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `Worker died` | Code crash during model loading | Check CloudWatch logs for traceback |
| `ModuleNotFoundError` | Missing dependency | Add to `code/requirements.txt` |
| `Invocation timed out` | Model loading too slow | Use larger instance or check code |
| `pip install failed` | Version conflicts | Pin compatible versions |

## Cost

- `ml.m5.large`: ~$0.115/hour
- Delete endpoints when not in use:
  ```bash
  aws sagemaker delete-endpoint --endpoint-name <name>
  ```
