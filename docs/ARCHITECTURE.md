# Architecture

This document describes the complete architecture of the **sagemaker-using_model** v1.x deployment stack.

## Overview

The stack provides an **OpenAI-compatible API** backed by a GPU-accelerated language model on AWS SageMaker, with a web-based chat interface (OpenWebUI) running on an EC2 instance.

![Architecture Overview](assets/architecture-overview.png)

### Components

| Component | AWS Service | Purpose |
|-----------|------------|---------|
| **OpenWebUI** | EC2 (t3.small) | Web-based chat UI (port 80, Elastic IP) |
| **API Gateway** | HTTP API | Public HTTPS endpoint with CORS |
| **Lambda Proxy** | Lambda (Python 3.11) | Translates OpenAI format to SageMaker |
| **vLLM Endpoint** | SageMaker | GPU inference with DJL-LMI container |

---

## Network Architecture

All resources deploy to **eu-west-1** (Ireland) in a single public subnet.

| Resource | Network | Access |
|----------|---------|--------|
| EC2 (OpenWebUI) | VPC public subnet | Elastic IP, SG allows :80/:443/:22 |
| API Gateway | AWS-managed | Public HTTPS endpoint |
| Lambda | AWS-managed | Invoked by API Gateway |
| SageMaker Endpoint | AWS-managed | Invoked by Lambda via boto3 |

**Security Groups:**
- `openwebui-sg`: Inbound TCP 80, 443, 22 (SSH from `AllowedSSHCidr`), all outbound

**IAM Roles (3):**

| Role | Trusted Service | Key Permissions |
|------|----------------|-----------------|
| SageMaker Execution Role | `sagemaker.amazonaws.com` | SageMakerFullAccess, ECR pull |
| Lambda Execution Role | `lambda.amazonaws.com` | CloudWatch Logs, `sagemaker:InvokeEndpoint` |
| EC2 Role | `ec2.amazonaws.com` | SSM Session Manager, S3 read (openwebui files) |

---

## Request Data Flow

1. **Client** sends an OpenAI-compatible request:
   ```json
   POST /v1/chat/completions
   {"messages": [{"role": "user", "content": "Hello"}], "max_tokens": 50}
   ```

2. **API Gateway** routes to Lambda via `AWS_PROXY` integration.

3. **Lambda** (`handler.py`) transforms the request:
   - `messages_to_prompt()` — concatenates message contents with `\n`
   - `invoke_sagemaker()` — wraps as vLLM payload: `{"inputs": "Hello", "parameters": {...}}`

4. **SageMaker Endpoint** generates tokens on GPU, returns text (with echoed prompt).

5. **Lambda** strips echoed prompt, wraps in OpenAI-compatible response format.

### API Routes

| Route | Method | Handler |
|-------|--------|---------|
| `/v1/chat/completions` | POST | `handle_chat_completion()` |
| `/v1/completions` | POST | `handle_chat_completion()` |
| `/v1/models` | GET | `handle_models_request()` |

---

## EC2 (OpenWebUI)

| Setting | Value |
|---------|-------|
| Instance | t3.small (2 vCPU, 2 GB RAM) |
| AMI | Amazon Linux 2023 |
| Image | `ghcr.io/open-webui/open-webui:main` (via Docker) |
| Port | 80 (mapped from container 8080) |
| IP | Elastic IP (static) |
| Auth | Disabled (`WEBUI_AUTH=false`) |
| Access | SSM Session Manager + optional SSH key |

**EC2 UserData** downloads `docker-compose.yml` and `setup.sh` from S3, installs Docker, and starts OpenWebUI.

---

## SageMaker Endpoint

| Setting | Value |
|---------|-------|
| Container | `djl-inference:0.28.0-lmi10.0.0-cu124` (DJL-LMI) |
| Instance | ml.g4dn.xlarge (NVIDIA T4, 16 GB GDDR6) |
| Model | Qwen/Qwen2.5-1.5B-Instruct |
| Batch mode | vLLM rolling batch |
| Precision | fp16 |
| Max tokens | 8192 |
| GPU utilization | 90% |
| Health check timeout | 900s |

---

## Cost

| Resource | Type | Cost/Hour |
|----------|------|-----------|
| SageMaker | ml.g4dn.xlarge | ~$0.74 |
| EC2 | t3.small | ~$0.02 |
| API Gateway | HTTP API | per request |
| **Total** | | **~$0.76/hr** |

**Always delete the stack when not in use.**

---

## CloudFormation Resources (21)

| # | Logical ID | Type |
|---|-----------|------|
| 1 | SageMakerExecutionRole | IAM::Role |
| 2 | SageMakerModel | SageMaker::Model |
| 3 | SageMakerEndpointConfig | SageMaker::EndpointConfig |
| 4 | SageMakerEndpoint | SageMaker::Endpoint |
| 5 | LambdaExecutionRole | IAM::Role |
| 6 | LambdaFunction | Lambda::Function |
| 7 | HttpApi | ApiGatewayV2::Api |
| 8 | HttpApiStage | ApiGatewayV2::Stage |
| 9 | LambdaIntegration | ApiGatewayV2::Integration |
| 10 | ChatCompletionsRoute | ApiGatewayV2::Route |
| 11 | CompletionsRoute | ApiGatewayV2::Route |
| 12 | ModelsRoute | ApiGatewayV2::Route |
| 13 | LambdaApiGatewayPermission | Lambda::Permission |
| 14 | EC2SecurityGroup | EC2::SecurityGroup |
| 15 | EC2Role | IAM::Role |
| 16 | EC2InstanceProfile | IAM::InstanceProfile |
| 17 | EC2Instance | EC2::Instance |
| 18 | EC2ElasticIP | EC2::EIP |
