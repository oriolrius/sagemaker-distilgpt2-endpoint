# API Gateway Lambda Function

Lambda function that proxies OpenAI-compatible requests to SageMaker vLLM endpoint.

## How it Works

1. Receives OpenAI-format requests from API Gateway
2. Converts chat messages to a prompt (for base models like distilgpt2)
3. Invokes SageMaker endpoint using boto3 (automatic SigV4 signing)
4. Formats response as OpenAI-compatible JSON

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/v1/models` | List available models |
| POST | `/v1/chat/completions` | Chat completions (OpenAI format) |
| POST | `/v1/completions` | Text completions |

## Request Format

```json
{
  "messages": [
    {"role": "user", "content": "The future of AI is"}
  ],
  "max_tokens": 100,
  "temperature": 0.7
}
```

## Response Format

```json
{
  "id": "chatcmpl-xxx",
  "object": "chat.completion",
  "model": "vllm-endpoint-xxx",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "..."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 10,
    "completion_tokens": 50,
    "total_tokens": 60
  }
}
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `SAGEMAKER_ENDPOINT_NAME` | Name of the SageMaker endpoint |
| `AWS_REGION` | AWS region (default: eu-north-1) |

## Local Testing

```python
# Test locally with a mock event
import lambda_function

event = {
    'httpMethod': 'POST',
    'path': '/v1/chat/completions',
    'body': '{"messages": [{"role": "user", "content": "Hello"}], "max_tokens": 50}'
}

class MockContext:
    aws_request_id = 'test-123'
    def get_remaining_time_in_millis(self):
        return 60000

response = lambda_function.lambda_handler(event, MockContext())
print(response)
```

## Note on Base Models

This function converts chat messages to a single prompt because distilgpt2 is a base model without a chat template. For instruction-tuned models, you may want to preserve the chat format.
