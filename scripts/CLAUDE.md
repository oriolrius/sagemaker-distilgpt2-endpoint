# scripts/

Standalone Python tools for deploying and testing SageMaker endpoints outside of CloudFormation.

**Note:** `deploy_vllm.py` is LEGACY — still uses DJL-LMI container directly, not updated for Fargate. Prefer `infra/deploy-full-stack.sh` for deployments.

## Usage

```bash
cd scripts
uv sync
uv run test-endpoint --endpoint-name <name>
uv run test-api-gateway --api-url <url>
```

## Files

| File | Purpose |
|------|---------|
| `src/sagemaker_tools/deploy_vllm.py` | Legacy: deploy SageMaker endpoint directly |
| `src/sagemaker_tools/test_openai_endpoint.py` | Test SageMaker endpoint |
| `src/sagemaker_tools/test_api_gateway.py` | Test API Gateway |
| `src/sagemaker_tools/cleanup.py` | Delete SageMaker resources |
