# Infrastructure - API Gateway + Lambda Proxy

CloudFormation infrastructure to expose the SageMaker vLLM endpoint via a public API Gateway.

## Architecture

```
┌──────────┐     ┌──────────────┐     ┌─────────────────┐
│  Client  │────▶│ API Gateway  │────▶│     Lambda      │────▶ SageMaker vLLM
│          │     │ (HTTP API)   │     │ (OpenAI proxy)  │     Endpoint
└──────────┘     └──────────────┘     └─────────────────┘
                  No Auth Required     SigV4 via boto3
```

## Features

- **No Authentication**: Public API (for development/testing)
- **OpenAI-Compatible**: `/v1/chat/completions`, `/v1/completions`, `/v1/models`
- **CORS Enabled**: Can be called from any origin
- **Low Latency**: HTTP API (not REST API) for better performance

## Deployment

```bash
# Deploy with auto-detected endpoint
./deploy.sh

# Or specify endpoint name
./deploy.sh vllm-endpoint-20260122-074720
```

## Cleanup

```bash
./delete.sh
```

## Files

| File | Description |
|------|-------------|
| `api-gateway-lambda.yaml` | CloudFormation template |
| `deploy.sh` | Deployment script |
| `delete.sh` | Cleanup script |

## Testing

After deployment, the script outputs test commands:

```bash
# List models
curl https://xxxxx.execute-api.eu-north-1.amazonaws.com/v1/models

# Chat completion
curl -X POST https://xxxxx.execute-api.eu-north-1.amazonaws.com/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"messages": [{"role": "user", "content": "The future of AI is"}], "max_tokens": 50}'
```

## Security Warning

This setup has **no authentication**. Do not use in production without adding:
- API Key authentication
- IAM authorization
- Lambda authorizer
- Usage plans and throttling
