# Verification Guide

How to verify that each layer of the deployed stack is working correctly. Work through the checks top-to-bottom -- each layer depends on the ones above it.

**Prerequisites:** AWS CLI configured, `uv` installed, stack deployed via `deploy-full-stack.sh`.

---

## Layer 1: Unit Tests (No AWS Required)

Verify the Lambda proxy code logic before touching anything in the cloud.

```bash
cd lambda/openai-proxy
uv sync --dev
uv run pytest -v
```

**Expected:** All tests pass (19 tests covering routing, CORS, JSON parsing, response formatting, error handling). SageMaker calls are mocked -- this only validates code logic.

```
tests/test_handler.py::TestCreateResponse::test_basic_response PASSED
tests/test_handler.py::TestCreateResponse::test_custom_headers PASSED
...
============================== 19 passed ==============================
```

You can also check code quality:

```bash
uv run ruff check src/ tests/
uv run ruff format --check src/ tests/
```

---

## Layer 2: AWS Credentials

Every subsequent check requires valid AWS credentials.

```bash
aws sts get-caller-identity
```

**Expected:** Returns your account ID, ARN, and user ID.

```json
{
    "UserId": "AROA...:your-session-name",
    "Account": "123456789012",
    "Arn": "arn:aws:sts::123456789012:assumed-role/..."
}
```

**If this fails:** Your credentials are missing or expired. See [DEBUGGING.md - Credential Issues](DEBUGGING.md#credential-issues).

---

## Layer 3: CloudFormation Stack Status

Confirm the stack deployed successfully and all resources were created.

```bash
aws cloudformation describe-stacks \
  --stack-name openai-sagemaker-stack \
  --region eu-west-1 \
  --query 'Stacks[0].StackStatus' \
  --output text
```

**Expected:** `CREATE_COMPLETE`

To see all stack outputs (API URL, endpoint name, ECS cluster/service):

```bash
aws cloudformation describe-stacks \
  --stack-name openai-sagemaker-stack \
  --region eu-west-1 \
  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
  --output table
```

Save these values -- you will need them for the checks below:

| Output | Variable | Example |
|--------|----------|---------|
| `ApiGatewayEndpoint` | `API_URL` | `https://abc123.execute-api.eu-west-1.amazonaws.com` |
| `SageMakerEndpointName` | `ENDPOINT_NAME` | `openai-sagemaker-stack-vllm-endpoint` |
| `OpenWebUIUrl` | `WEBUI_URL` | `http://10.0.1.42:8080` |

For convenience, export them:

```bash
STACK_NAME="openai-sagemaker-stack"
REGION="eu-west-1"

API_URL=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiGatewayEndpoint`].OutputValue' --output text)

ENDPOINT_NAME=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`SageMakerEndpointName`].OutputValue' --output text)

# Discover the Fargate task IP
TASK_ARN=$(aws ecs list-tasks --cluster ${STACK_NAME}-cluster --service-name ${STACK_NAME}-openwebui \
  --region $REGION --query 'taskArns[0]' --output text)

ENI_ID=$(aws ecs describe-tasks --cluster ${STACK_NAME}-cluster --tasks $TASK_ARN \
  --region $REGION \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text)

FARGATE_IP=$(aws ec2 describe-network-interfaces --network-interface-ids $ENI_ID \
  --region $REGION --query 'NetworkInterfaces[0].Association.PublicIp' --output text)

echo "API_URL=$API_URL"
echo "ENDPOINT_NAME=$ENDPOINT_NAME"
echo "FARGATE_IP=$FARGATE_IP"
```

---

## Layer 4: SageMaker Endpoint

The SageMaker endpoint is the slowest resource to provision (~7-10 minutes). It must be `InService` before any inference works.

### Check Status

```bash
aws sagemaker describe-endpoint \
  --endpoint-name $ENDPOINT_NAME \
  --region $REGION \
  --query '{Status: EndpointStatus, Name: EndpointName}'
```

**Expected:**

```json
{
    "Status": "InService",
    "Name": "openai-sagemaker-stack-vllm-endpoint"
}
```

| Status | Meaning | Action |
|--------|---------|--------|
| `InService` | Ready | Continue to the next check |
| `Creating` | Still provisioning | Wait (up to 10 minutes) |
| `Failed` | Something broke | See [DEBUGGING.md - SageMaker Endpoint Failed](DEBUGGING.md#sagemaker-endpoint-failed) |
| `RollingBack` | Update failed | Check CloudWatch logs |

### Invoke Directly (Bypass Lambda and API Gateway)

This tests the model container in isolation using the legacy `inputs` + `parameters` format:

```bash
aws sagemaker-runtime invoke-endpoint \
  --endpoint-name $ENDPOINT_NAME \
  --content-type application/json \
  --body '{"inputs": "The capital of France is", "parameters": {"max_new_tokens": 30}}' \
  --region $REGION \
  /dev/stdout
```

**Expected:** A JSON response containing generated text. The model continues the prompt.

```json
[{"generated_text": "The capital of France is Paris. The city of..."}]
```

Or use the test script for a more thorough check (tests OpenAI chat format, streaming, and legacy format):

```bash
cd scripts
uv sync
uv run test-endpoint $ENDPOINT_NAME
```

**Expected:** All three tests print `[PASS]`.

---

## Layer 5: Lambda Function

The Lambda translates OpenAI-format requests into SageMaker invocations. Verify it was deployed correctly.

### Check Lambda Exists and Has Correct Configuration

```bash
aws lambda get-function-configuration \
  --function-name ${STACK_NAME}-openai-proxy \
  --region $REGION \
  --query '{Runtime: Runtime, Handler: Handler, Timeout: Timeout, MemorySize: MemorySize, Env: Environment.Variables}'
```

**Expected:**

```json
{
    "Runtime": "python3.11",
    "Handler": "index.lambda_handler",
    "Timeout": 60,
    "MemorySize": 256,
    "Env": {
        "SAGEMAKER_ENDPOINT_NAME": "openai-sagemaker-stack-vllm-endpoint",
        "AWS_REGION_NAME": "eu-west-1"
    }
}
```

Key things to verify:
- `SAGEMAKER_ENDPOINT_NAME` matches the actual endpoint name from Layer 4
- `Timeout` is 60 seconds (enough for SageMaker cold starts)

### Invoke Lambda Directly (Bypass API Gateway)

```bash
aws lambda invoke \
  --function-name ${STACK_NAME}-openai-proxy \
  --region $REGION \
  --payload '{"requestContext":{"http":{"method":"GET"}},"rawPath":"/v1/models"}' \
  /dev/stdout
```

**Expected:** The Lambda returns the models list:

```json
{"statusCode": 200, "headers": {...}, "body": "{\"object\": \"list\", \"data\": [...]}"}
```

---

## Layer 6: API Gateway (Full Chain)

This tests the entire path: API Gateway -> Lambda -> SageMaker.

### Test 1: List Models (GET)

```bash
curl -s "$API_URL/v1/models" | python3 -m json.tool
```

**Expected:**

```json
{
    "object": "list",
    "data": [
        {
            "id": "openai-sagemaker-stack-vllm-endpoint",
            "object": "model",
            "created": 1677610602,
            "owned_by": "sagemaker"
        }
    ]
}
```

### Test 2: Chat Completion (POST)

```bash
curl -s -X POST "$API_URL/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "The future of artificial intelligence is"}], "max_tokens": 50}' \
  | python3 -m json.tool
```

**Expected:** A response with generated text in `choices[0].message.content`:

```json
{
    "id": "chatcmpl-...",
    "object": "chat.completion",
    "model": "openai-sagemaker-stack-vllm-endpoint",
    "choices": [
        {
            "index": 0,
            "message": {
                "role": "assistant",
                "content": "...generated text..."
            },
            "finish_reason": "stop"
        }
    ],
    "usage": {
        "prompt_tokens": 7,
        "completion_tokens": 50,
        "total_tokens": 57
    }
}
```

### Test 3: CORS Preflight (OPTIONS)

```bash
curl -s -X OPTIONS "$API_URL/v1/chat/completions" \
  -H "Origin: http://localhost" \
  -H "Access-Control-Request-Method: POST" \
  -D - -o /dev/null 2>&1 | head -10
```

**Expected:** `200` status with CORS headers (`Access-Control-Allow-Origin`, `Access-Control-Allow-Methods`).

### Automated Test Script

For a comprehensive test of all three API endpoints:

```bash
cd scripts
uv sync
uv run python -m sagemaker_tools.test_api_gateway "$API_URL"
```

**Expected:** All tests print `[PASS]` and the script finishes with `ALL TESTS PASSED!`.

---

## Layer 7: OpenWebUI

The web chat interface running as an ECS Fargate task, connecting to the API Gateway.

### Check ECS Fargate Task Is Running

```bash
aws ecs describe-services \
  --cluster ${STACK_NAME}-cluster \
  --services ${STACK_NAME}-openwebui \
  --region $REGION \
  --query 'services[0].{Status: status, Running: runningCount, Desired: desiredCount}' \
  --output table
```

**Expected:** Status is `ACTIVE` with `Running` equal to `Desired` (typically 1).

### Check OpenWebUI Responds

```bash
curl -s -o /dev/null -w "%{http_code}" "http://$FARGATE_IP:8080"
```

**Expected:** `200` (the page loads). If you get `000` (connection refused), wait 3-5 minutes after stack completion -- the container is still starting.

### Open in Browser

Navigate to `http://<FARGATE_IP>:8080` in your browser. You should see the OpenWebUI chat interface.

1. The model `openai-sagemaker-stack-vllm-endpoint` appears in the model selector
2. Type a prompt like `The most important invention is` and press Enter
3. You get a generated response within a few seconds

### Debug via CloudWatch Logs

If OpenWebUI does not load, check the Fargate task status and container logs:

```bash
# Check task status and stop reason (if stopped)
aws ecs describe-tasks --cluster ${STACK_NAME}-cluster --tasks $TASK_ARN \
  --region $REGION \
  --query 'tasks[0].{Status: lastStatus, StopReason: stoppedReason, Health: healthStatus}'

# Tail the container logs from CloudWatch
aws logs tail /ecs/${STACK_NAME}-openwebui --region $REGION --since 30m --follow
```

If the task keeps restarting, check for configuration errors:

```bash
# List recent stopped tasks
aws ecs list-tasks --cluster ${STACK_NAME}-cluster --service-name ${STACK_NAME}-openwebui \
  --desired-status STOPPED --region $REGION

# Check events on the service for scheduling/health-check failures
aws ecs describe-services --cluster ${STACK_NAME}-cluster --services ${STACK_NAME}-openwebui \
  --region $REGION --query 'services[0].events[:5]'
```

---

## Quick Summary Checklist

Run through this table to confirm everything works:

| # | Check | Command | Expected |
|---|-------|---------|----------|
| 1 | Unit tests | `cd lambda/openai-proxy && uv run pytest -v` | All pass |
| 2 | AWS credentials | `aws sts get-caller-identity` | Returns account info |
| 3 | Stack status | `aws cloudformation describe-stacks --stack-name $STACK_NAME --query 'Stacks[0].StackStatus'` | `CREATE_COMPLETE` |
| 4 | Endpoint status | `aws sagemaker describe-endpoint --endpoint-name $ENDPOINT_NAME --query EndpointStatus` | `InService` |
| 5 | SageMaker direct | `aws sagemaker-runtime invoke-endpoint --endpoint-name $ENDPOINT_NAME --body '{"inputs":"Hello"}' /dev/stdout` | Returns JSON |
| 6 | Lambda direct | `aws lambda invoke --function-name ${STACK_NAME}-openai-proxy --payload '...' /dev/stdout` | Returns 200 |
| 7 | API GET /v1/models | `curl $API_URL/v1/models` | Model list JSON |
| 8 | API POST /v1/chat/completions | `curl -X POST $API_URL/v1/chat/completions -d '...'` | Generated text |
| 9 | ECS Fargate task | `aws ecs describe-services --cluster ${STACK_NAME}-cluster --services ${STACK_NAME}-openwebui --query 'services[0].runningCount'` | `1` |
| 10 | OpenWebUI HTTP | `curl -o /dev/null -w "%{http_code}" http://$FARGATE_IP:8080` | `200` |
| 11 | OpenWebUI browser | Open `http://$FARGATE_IP:8080` | Chat interface loads |

If any check fails, see [DEBUGGING.md](DEBUGGING.md) for diagnosis and resolution.
