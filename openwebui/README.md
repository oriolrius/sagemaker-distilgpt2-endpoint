# OpenWebUI with SageMaker vLLM Endpoint

Local development/testing setup for OpenWebUI connected to your SageMaker vLLM endpoint via LiteLLM proxy.

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌──────────────────┐
│  OpenWebUI  │────▶│   LiteLLM   │────▶│ SageMaker vLLM   │
│  :3000      │     │   :4001     │     │ Endpoint         │
└─────────────┘     └─────────────┘     └──────────────────┘
                    (SigV4 signing)
```

LiteLLM handles AWS SigV4 authentication required by SageMaker endpoints.

## Prerequisites

- Docker and Docker Compose installed
- AWS credentials configured (with access to SageMaker)
- A running SageMaker vLLM endpoint (e.g., `vllm-endpoint-*`)

## Quick Start

```bash
# 1. Ensure AWS credentials are configured
aws sts get-caller-identity --region eu-north-1

# 2. Run setup script (generates .env and updates config)
chmod +x setup_env.sh
./setup_env.sh

# 3. Start services
docker compose up -d

# 4. Open OpenWebUI
open http://localhost:3000
```

Select model `distilgpt2` or `sagemaker-vllm` in the UI.

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
curl -s http://localhost:4001/v1/models \
  -H "Authorization: Bearer sk-1234" | jq '.data[].id'

# Test completion (statement format - works best)
curl -s http://localhost:4001/v1/chat/completions \
  -H "Authorization: Bearer sk-1234" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "distilgpt2",
    "messages": [{"role": "user", "content": "The future of artificial intelligence will depend on"}],
    "max_tokens": 100
  }' | jq -r '.choices[0].message.content'

# Test Q&A format
curl -s http://localhost:4001/v1/chat/completions \
  -H "Authorization: Bearer sk-1234" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "distilgpt2",
    "messages": [{"role": "user", "content": "Q: What is photosynthesis?\nA:"}],
    "max_tokens": 100
  }' | jq -r '.choices[0].message.content'
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | OpenWebUI + LiteLLM services |
| `litellm_config.yaml` | LiteLLM proxy configuration |
| `.env` | AWS credentials (gitignored) |
| `setup_env.sh` | Auto-generate .env from AWS CLI |

## Configuration Details

### Why Two Models in OpenWebUI?

You'll see two models (`distilgpt2` and `sagemaker-vllm`) in OpenWebUI, but there's only **one SageMaker endpoint**. This is because LiteLLM defines **model aliases** - multiple names that route to the same backend:

```yaml
model_list:
  - model_name: distilgpt2        # Alias 1 → same endpoint
  - model_name: sagemaker-vllm    # Alias 2 → same endpoint
```

Both names point to the same `vllm-endpoint-*` in SageMaker. This is useful for:
- Using friendly names (`distilgpt2`) instead of endpoint IDs
- Testing different configurations per alias (e.g., different default parameters)
- Migrating clients gradually when changing endpoints

You can remove one alias from `litellm_config.yaml` if you prefer a single model in the UI.

### LiteLLM Config (`litellm_config.yaml`)

```yaml
model_list:
  - model_name: distilgpt2
    litellm_params:
      model: sagemaker/vllm-endpoint-XXXXXX  # Use 'sagemaker/' for base models
```

**Important:** Use `sagemaker/` prefix (not `sagemaker_chat/`) for base models without chat templates. The `sagemaker_chat/` prefix requires models with a tokenizer chat template.

### Environment Variables (`.env`)

```bash
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
AWS_SESSION_TOKEN=...        # Required for temporary credentials
AWS_REGION_NAME=eu-north-1
LITELLM_MASTER_KEY=sk-1234   # API key for LiteLLM
```

## Updating Endpoint

When you redeploy the SageMaker endpoint:

```bash
# Re-run setup to detect new endpoint
./setup_env.sh
docker compose restart litellm
```

Or manually update the endpoint name in both `litellm_config.yaml` and `.env`.

## Troubleshooting

### Check container status
```bash
docker compose ps
```

### View LiteLLM logs
```bash
docker compose logs litellm --tail 50
```

### View OpenWebUI logs
```bash
docker compose logs openwebui --tail 50
```

### Test LiteLLM health
```bash
curl http://localhost:4001/health
```

### AWS credentials expired
```bash
# Refresh credentials and restart
./setup_env.sh
docker compose restart litellm
```

### Model returns empty or random output
- Use statement format instead of questions (see "Understanding distilgpt2" section)
- Check LiteLLM logs for errors: `docker compose logs litellm`

### Port 4001 already in use
```bash
# Find what's using the port
lsof -i :4001
# Or change the port in docker-compose.yml
```

## Cleanup

```bash
# Stop containers
docker compose down

# Stop and remove volumes (deletes OpenWebUI data)
docker compose down -v
```

## Notes

- **Ports**: OpenWebUI on `:3000`, LiteLLM on `:4001`
- **Authentication**: OpenWebUI auth is disabled (`WEBUI_AUTH=false`) for local dev
- **Session tokens**: AWS session tokens expire (typically 1-12 hours). Re-run `setup_env.sh` when they do.
- **Model quality**: distilgpt2 is a small 82M parameter model. For better responses, deploy a larger instruction-tuned model.
