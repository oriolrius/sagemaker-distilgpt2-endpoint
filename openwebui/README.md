# OpenWebUI with SageMaker vLLM Endpoint

Local development/testing setup for OpenWebUI connected to your SageMaker vLLM endpoint via API Gateway.

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌────────────┐     ┌─────────────────┐
│  OpenWebUI  │────▶│ API Gateway  │────▶│   Lambda   │────▶│ SageMaker vLLM  │
│  :49200     │     │ (public)     │     │  (proxy)   │     │   Endpoint      │
└─────────────┘     └──────────────┘     └────────────┘     └─────────────────┘
   (OpenAI API)       No Auth            SigV4 signing         (vLLM)
```

### Why this architecture?

1. **API Gateway** exposes a public HTTP endpoint (no auth for dev/testing)
2. **Lambda** receives OpenAI-format requests and forwards them to SageMaker
3. **Lambda uses boto3** which automatically handles AWS SigV4 signing
4. **OpenWebUI** connects directly to API Gateway as if it were OpenAI

**No LiteLLM needed** - the Lambda function handles the translation and AWS authentication.

## Prerequisites

- Docker and Docker Compose installed
- Infrastructure deployed (see `../infra/README.md`)

## Quick Start

```bash
# 1. Deploy infrastructure first (if not done)
cd ../infra
./deploy.sh

# 2. Generate .env with API Gateway URL
cd ../openwebui
./setup_env.sh

# 3. Start OpenWebUI
docker compose up -d

# 4. Open browser
open http://localhost:49200
```

Select the model (named after your SageMaker endpoint) in the UI.

## Understanding distilgpt2 (Base Model)

distilgpt2 is a **base model** (not instruction-tuned), which means:

| Prompt Type | Works? | Example |
|-------------|--------|---------|
| Text completion | Yes | `"The capital of France is"` → `"Paris, the largest city..."` |
| Q&A format | Partial | `"Q: What is AI?\nA:"` → `"AI is a field of..."` |
| Direct questions | No | `"What is AI?"` → empty or random output |

**Best practices for distilgpt2:**
- Use **statement completions**: `"The future of AI will depend on"`
- Use **Q&A format** with explicit markers: `"Q: ...\nA:"`
- Expect **repetitive output** (no repetition penalty configured)
- For proper chat behavior, deploy an **instruction-tuned model** (Llama-2-chat, Mistral-Instruct, etc.)

## Test the API Directly

```bash
# List available models
curl https://YOUR-API-ID.execute-api.eu-north-1.amazonaws.com/v1/models

# Test completion (statement format - works best)
curl -X POST https://YOUR-API-ID.execute-api.eu-north-1.amazonaws.com/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "messages": [{"role": "user", "content": "The future of artificial intelligence will depend on"}],
    "max_tokens": 100
  }'
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | OpenWebUI service |
| `.env` | API Gateway URL (gitignored) |
| `.env.example` | Template for .env |
| `setup_env.sh` | Auto-generate .env from CloudFormation |
| `data/` | OpenWebUI data (SQLite, uploads, cache) |

## Configuration

### Environment Variables (`.env`)

```bash
OPENAI_API_BASE_URL=https://xxxxx.execute-api.eu-north-1.amazonaws.com/v1
```

The setup script automatically fetches this from the CloudFormation stack output.

## Troubleshooting

### Check container status
```bash
docker compose ps
```

### View OpenWebUI logs
```bash
docker compose logs openwebui --tail 50
```

### Test API Gateway directly
```bash
curl $(grep OPENAI_API_BASE_URL .env | cut -d= -f2)/models
```

### Infrastructure not deployed
```bash
cd ../infra && ./deploy.sh
```

## Cleanup

```bash
# Stop OpenWebUI
docker compose down

# Delete infrastructure (API Gateway + Lambda)
cd ../infra && ./delete.sh
```

## Notes

- **Port**: OpenWebUI on `:49200`
- **Authentication**: OpenWebUI auth is disabled (`WEBUI_AUTH=false`) for local dev
- **API Gateway**: Public endpoint with no authentication (for dev only)
- **Data persistence**: SQLite database in `./data/openwebui/`
