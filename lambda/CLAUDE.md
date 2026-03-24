# lambda/

OpenAI-compatible API proxy that translates requests to SageMaker format.

## Structure

```
lambda/openai-proxy/
├── pyproject.toml          # uv project (boto3 dep, pytest/ruff/moto devDeps)
├── src/
│   ├── index.py            # Entry point: lambda_handler
│   └── openai_proxy/
│       └── handler.py      # All request handling logic
└── tests/
    └── test_handler.py     # 19 unit tests
```

## Key Functions (handler.py)

| Function | Purpose |
|----------|---------|
| `lambda_handler()` | Routes by HTTP method/path |
| `handle_chat_completion()` | POST /v1/chat/completions |
| `handle_models_request()` | GET /v1/models |
| `invoke_sagemaker()` | boto3 `InvokeEndpoint` call |
| `messages_to_prompt()` | Joins message contents with `\n` (no chat template) |
| `create_chat_completion_response()` | Wraps output in OpenAI format |

## Data Flow

```
OpenAI messages → messages_to_prompt() → plain text
→ invoke_sagemaker({"inputs": text, "parameters": {...}})
→ strip echoed prompt from response
→ wrap in OpenAI chat completion JSON
```

## Development

```bash
cd lambda/openai-proxy
uv sync --dev
uv run pytest -v                                    # run tests
uv run pytest --cov=openai_proxy --cov-report=term-missing  # coverage
uv run ruff check src/ tests/                       # lint
uv run ruff format src/ tests/                      # format
```

## Environment Variables (runtime)

| Variable | Set by |
|----------|--------|
| `SAGEMAKER_ENDPOINT_NAME` | CloudFormation |
| `AWS_REGION_NAME` | CloudFormation |
