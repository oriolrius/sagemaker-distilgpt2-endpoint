# SageMaker LLM Endpoint + OpenAI API + OpenWebUI

Deploy a HuggingFace language model on AWS SageMaker with vLLM, exposed via an OpenAI-compatible API, with OpenWebUI for a chat interface.

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌────────────┐     ┌─────────────────┐
│  OpenWebUI  │────▶│ API Gateway  │────▶│   Lambda   │────▶│ SageMaker vLLM  │
│(Fargate :8080)│   │ (HTTP API)   │     │  (proxy)   │     │   Endpoint      │
└─────────────┘     └──────────────┘     └────────────┘     └─────────────────┘
     ▲                    ▲
     │                    │
     └── Browser ─────────┴── API Clients (curl, Python, etc.)
```

### Components

| Component | Description |
|-----------|-------------|
| **SageMaker Endpoint** | Runs your HuggingFace model on GPU via vLLM |
| **Lambda** | Proxies OpenAI-format requests to SageMaker (handles SigV4 signing) |
| **API Gateway** | Public HTTP API (OpenAI-compatible) |
| **ECS Fargate + OpenWebUI** | Web-based chat interface |

## Quick Start

### Prerequisites

- AWS CLI configured with credentials
- GPU quota for ml.g4dn.xlarge (check Service Quotas)
- [uv](https://github.com/astral-sh/uv) (Python package manager) for Lambda packaging

### Deploy

```bash
cd infra/
./deploy-full-stack.sh
```

Deployment takes ~7-10 minutes (mostly SageMaker endpoint startup).

### Access

After deployment:
- **OpenWebUI**: `http://<fargate-ip>:8080` (shown in output; IP is dynamic and may change on task restart)
- **API**: `https://<api-id>.execute-api.eu-west-1.amazonaws.com`

### Test API

```bash
# List models
curl https://<api-endpoint>/v1/models

# Chat completion
curl -X POST https://<api-endpoint>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "The future of AI is"}], "max_tokens": 50}'
```

### Cleanup

```bash
cd infra/
./delete-full-stack.sh
```

## Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--model-id` | Qwen/Qwen2.5-1.5B-Instruct | HuggingFace model ID |
| `--sagemaker-instance` | ml.g4dn.xlarge | GPU instance type |
| `--stack-name` | openai-sagemaker-stack | CloudFormation stack name |

### Example: Deploy a different model

```bash
./deploy-full-stack.sh \
  --model-id TinyLlama/TinyLlama-1.1B-Chat-v1.0 \
  --sagemaker-instance ml.g4dn.xlarge
```

## Cost

| Resource | Type | Cost |
|----------|------|------|
| SageMaker | ml.g4dn.xlarge | ~$0.74/hour |
| Fargate | 0.5 vCPU/1GB | ~$0.03/hour |
| API Gateway | HTTP API | ~$1/million requests |

**Total**: ~$0.77/hour (~$555/month if 24/7)

⚠️ **Remember to delete resources when not in use!**

## Notes

### Default Model

The default model is **Qwen/Qwen2.5-1.5B-Instruct**, a 1.5B parameter instruction-tuned model. It can follow instructions, answer questions, write code, and hold conversations in multiple languages. It fits easily on a T4 GPU (~3 GB in fp16).

### Security

⚠️ This setup is for **development/testing**:
- No API authentication
- OpenWebUI auth disabled

For production, add API Gateway authentication and enable OpenWebUI auth.

## Project Structure

```
.
├── lambda/
│   └── openai-proxy/            # Lambda function source
│       ├── pyproject.toml       # Python project config (uv)
│       ├── src/
│       │   ├── index.py         # Lambda entry point
│       │   └── openai_proxy/
│       │       └── handler.py   # Request handlers
│       └── tests/
│           └── test_handler.py  # Unit tests
├── openwebui/                   # OpenWebUI configuration
│   ├── docker-compose.yml       # Docker Compose config
│   ├── setup.sh                 # Setup script
│   └── README.md
├── infra/
│   ├── full-stack.yaml          # CloudFormation template
│   ├── deploy-full-stack.sh     # Deployment script
│   ├── delete-full-stack.sh     # Cleanup script
│   └── README.md
└── README.md                    # This file
```

## Development

### Lambda Function

```bash
cd lambda/openai-proxy
uv sync --dev

# Run tests
uv run pytest

# Lint
uv run ruff check src/ tests/
```

### OpenWebUI (Local)

Run OpenWebUI locally (without CloudFormation):

```bash
cd openwebui/
cp .env.example .env
# Edit .env and set OPENAI_API_BASE_URL

./setup.sh
# Or: docker-compose up -d
```

## License

MIT
