# Deployment Notes

This document describes the step-by-step deployment process for the SageMaker vLLM + OpenAI API + OpenWebUI stack.

## Deployment Overview

| Step | Duration | Description |
|------|----------|-------------|
| 1. AWS Credentials | ~1 min | Configure AWS CLI with valid credentials |
| 2. Find VPC/Subnet | ~30 sec | Identify network resources for EC2 |
| 3. Check GPU Quota | ~30 sec | Verify SageMaker quota for ml.g4dn.xlarge |
| 4. Package Lambda | ~30 sec | Create ZIP with dependencies |
| 5. Create S3 Bucket | ~10 sec | Create bucket for artifacts |
| 6. Upload Files | ~30 sec | Upload Lambda + OpenWebUI files to S3 |
| 7. Deploy CloudFormation | **15-20 min** | Create all AWS resources |
| 8. Test Endpoints | ~1 min | Verify API and OpenWebUI work |
| 9. Cleanup (when done) | ~5-10 min | Delete all resources to stop billing |
| 10. Verify Cleanup | ~1 min | Confirm all resources are deleted |

**Total deployment time: ~20-25 minutes** (mostly waiting for SageMaker endpoint)

**⚠️ IMPORTANT:** Always run cleanup (Step 9) when you're done testing to avoid ongoing charges (~$0.76/hour).

---

## Step 1: AWS Credentials

**Purpose:** AWS CLI needs valid credentials to create resources.

**What we did:**
```bash
uv run /home/oriol/.claude/skills/aws-credentials-setup/scripts/setup_aws_credentials.py --from-sandbox --skip-github
```

This automated script:
1. Logs into AWS Innovation Sandbox portal
2. Extracts temporary credentials (Access Key, Secret Key, Session Token)
3. Configures local AWS CLI (`~/.aws/credentials`)

**Verification:**
```bash
aws sts get-caller-identity
```

**Notes:**
- Credentials expire after ~12 hours
- If deployment fails with "ExpiredToken", refresh credentials first

---

## Step 2: Find VPC and Subnet

**Purpose:** The EC2 instance needs a VPC and public subnet to be accessible from the internet.

**What we did:**
```bash
# List VPCs
aws ec2 describe-vpcs --region eu-north-1 \
  --query 'Vpcs[*].[VpcId,Tags[?Key==`Name`].Value|[0],CidrBlock,IsDefault]' \
  --output table

# List public subnets in the VPC
aws ec2 describe-subnets --region eu-north-1 \
  --filters Name=vpc-id,Values=vpc-0496b1fd0ee93bda5 \
  --query 'Subnets[?MapPublicIpOnLaunch==`true`].[SubnetId,AvailabilityZone,CidrBlock]' \
  --output table
```

**Results:**
- VPC: `vpc-0496b1fd0ee93bda5` (default VPC, 172.31.0.0/16)
- Subnet: `subnet-0d61bc37e295a50ac` (eu-north-1a, public)

**Notes:**
- Must use a **public subnet** (MapPublicIpOnLaunch=true) for OpenWebUI to be accessible
- Any availability zone works, but instance types vary by AZ

---

## Step 3: Check GPU Quota

**Purpose:** SageMaker GPU instances require quota approval. Without quota, deployment fails.

**What we did:**
```bash
aws service-quotas list-service-quotas --service-code sagemaker --region eu-north-1 \
  --query 'Quotas[*].[QuotaName,Value]' --output text | grep -i "g4dn.*endpoint"
```

**Results:**
```
ml.g4dn.xlarge for endpoint usage    1.0
```

**Notes:**
- Quota of 1.0 means we can run 1 instance of ml.g4dn.xlarge
- If quota is 0, request increase via AWS Service Quotas console
- Quota requests can take 1-3 days to approve

---

## Step 4: Package Lambda Function

**Purpose:** Create a deployment package (ZIP) containing Lambda code and dependencies.

**What we did:**
```bash
# Create clean build directory
rm -rf .build && mkdir -p .build/package

# Install dependencies (boto3)
uv pip install --target .build/package boto3 --quiet

# Copy source code
cp -r lambda/openai-proxy/src/* .build/package/

# Create ZIP
cd .build/package && zip -r ../lambda-openai-proxy.zip . -q
```

**Result:** `.build/lambda-openai-proxy.zip` (15MB)

**Notes:**
- boto3 is included in Lambda runtime, but we package it for consistency
- The ZIP contains: `index.py`, `openai_proxy/handler.py`, and boto3 dependencies

---

## Step 5: Create S3 Bucket

**Purpose:** S3 stores the Lambda deployment package and OpenWebUI configuration files.

**What we did:**
```bash
STACK_NAME="openai-sagemaker-stack"
REGION="eu-north-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
LAMBDA_S3_BUCKET="${STACK_NAME}-lambda-${AWS_ACCOUNT_ID}-${REGION}"

aws s3api create-bucket \
    --bucket "$LAMBDA_S3_BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
```

**Result:** `openai-sagemaker-stack-lambda-753916465480-eu-north-1`

**Notes:**
- Bucket name must be globally unique
- We include account ID and region to ensure uniqueness
- LocationConstraint is required for regions other than us-east-1

---

## Step 6: Upload Files to S3

**Purpose:** CloudFormation references these files during deployment.

**What we did:**
```bash
# Upload Lambda package
aws s3 cp .build/lambda-openai-proxy.zip \
  "s3://$LAMBDA_S3_BUCKET/lambda/$STACK_NAME/lambda-openai-proxy.zip"

# Upload OpenWebUI files
aws s3 cp openwebui/docker-compose.yml "s3://$LAMBDA_S3_BUCKET/openwebui/docker-compose.yml"
aws s3 cp openwebui/setup.sh "s3://$LAMBDA_S3_BUCKET/openwebui/setup.sh"
```

**S3 bucket contents after upload:**
```
lambda/openai-sagemaker-stack/lambda-openai-proxy.zip  (15MB)
openwebui/docker-compose.yml                           (588B)
openwebui/setup.sh                                     (2.4KB)
```

**Notes:**
- Lambda code is referenced by CloudFormation's `AWS::Lambda::Function`
- OpenWebUI files are downloaded by EC2 during startup (UserData)

---

## Step 7: Deploy CloudFormation Stack

**Purpose:** Create all AWS resources in a single, coordinated deployment.

**What we did:**
```bash
aws cloudformation deploy \
    --region "eu-north-1" \
    --stack-name "openai-sagemaker-stack" \
    --template-file "infra/full-stack.yaml" \
    --parameter-overrides \
        HuggingFaceModelId="distilgpt2" \
        SageMakerInstanceType="ml.g4dn.xlarge" \
        EC2InstanceType="t3.small" \
        VpcId="vpc-0496b1fd0ee93bda5" \
        SubnetId="subnet-0d61bc37e295a50ac" \
        LambdaS3Bucket="$LAMBDA_S3_BUCKET" \
        LambdaS3Key="lambda/$STACK_NAME/lambda-openai-proxy.zip" \
    --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset
```

**Resources created (in order):**

| Resource | Type | Purpose | Creation Time |
|----------|------|---------|---------------|
| SageMakerExecutionRole | IAM Role | Allows SageMaker to access ECR, S3 | ~30 sec |
| LambdaExecutionRole | IAM Role | Allows Lambda to invoke SageMaker | ~30 sec |
| EC2Role | IAM Role | Allows EC2 to access S3, SSM | ~30 sec |
| EC2SecurityGroup | Security Group | Allows HTTP/HTTPS/SSH to EC2 | ~10 sec |
| HttpApi | API Gateway | Public HTTP API endpoint | ~10 sec |
| HttpApiStage | API Gateway Stage | Default stage with auto-deploy | ~5 sec |
| SageMakerModel | SageMaker Model | vLLM container configuration | ~30 sec |
| SageMakerEndpointConfig | Endpoint Config | Instance type, variant settings | ~10 sec |
| **SageMakerEndpoint** | **Endpoint** | **Actual GPU instance** | **15-20 min** |
| EC2InstanceProfile | Instance Profile | Attaches role to EC2 | ~30 sec |
| EC2Instance | EC2 Instance | Runs OpenWebUI | ~2 min |
| LambdaFunction | Lambda | OpenAI proxy code | ~30 sec |
| LambdaIntegration | API Integration | Connects API GW to Lambda | ~10 sec |
| API Routes | API Routes | /v1/models, /v1/chat/completions | ~10 sec |
| EC2ElasticIP | Elastic IP | Static public IP for EC2 | ~10 sec |

**Why SageMaker takes 15-20 minutes:**
1. Provisions ml.g4dn.xlarge instance (GPU)
2. Pulls DJL-LMI container image (~10GB)
3. Downloads model from HuggingFace (distilgpt2 ~300MB)
4. Loads model into GPU memory
5. Runs health checks

---

## Step 8: Test Endpoints

**Purpose:** Verify all components are working.

### Test API Gateway - List Models
```bash
curl https://txuyv5fn08.execute-api.eu-north-1.amazonaws.com/v1/models
```

**Expected response:**
```json
{
  "object": "list",
  "data": [{
    "id": "openai-sagemaker-stack-vllm-endpoint",
    "object": "model",
    "created": 1677610602,
    "owned_by": "sagemaker"
  }]
}
```

### Test API Gateway - Chat Completions
```bash
curl -X POST https://txuyv5fn08.execute-api.eu-north-1.amazonaws.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "The future of AI is"}], "max_tokens": 50}'
```

**Expected response:**
```json
{
  "id": "chatcmpl-xxx",
  "object": "chat.completion",
  "model": "openai-sagemaker-stack-vllm-endpoint",
  "choices": [{
    "index": 0,
    "message": {"role": "assistant", "content": "...generated text..."},
    "finish_reason": "stop"
  }],
  "usage": {"prompt_tokens": 5, "completion_tokens": 20, "total_tokens": 25}
}
```

### Test OpenWebUI
```bash
curl -s -o /dev/null -w "%{http_code}" http://16.16.247.99
```

**Expected:** `200`

---

## Issues Encountered

### Issue 1: EC2 Instance Type Not Available

**Error:**
```
The requested configuration is currently not supported.
```

**Cause:** `t3a.small` is not available in `eu-north-1` region.

**Solution:** Changed to `t3.small` which is available in all eu-north-1 AZs.

**How to check instance availability:**
```bash
aws ec2 describe-instance-type-offerings --region eu-north-1 \
  --location-type availability-zone \
  --filters Name=instance-type,Values=t3.small \
  --query 'InstanceTypeOfferings[*].[Location,InstanceType]' --output table
```

---

## Deployment Outputs

After successful deployment:

| Output | Value |
|--------|-------|
| API Gateway | `https://txuyv5fn08.execute-api.eu-north-1.amazonaws.com` |
| OpenWebUI | `http://16.16.247.99` |
| SageMaker Endpoint | `openai-sagemaker-stack-vllm-endpoint` |
| EC2 Instance | `i-0439c428039acd347` |
| EC2 Public IP | `16.16.247.99` |

---

## Cost Summary

| Resource | Type | Hourly Cost |
|----------|------|-------------|
| SageMaker Endpoint | ml.g4dn.xlarge | ~$0.74 |
| EC2 Instance | t3.small | ~$0.02 |
| API Gateway | HTTP API | ~$1/million requests |
| S3 | Storage | Negligible |
| Elastic IP | Attached | Free |

**Total: ~$0.76/hour (~$18/day, ~$550/month if 24/7)**

---

## Step 9: Cleanup (Delete All Resources)

**Purpose:** Delete all resources to stop billing. **This is critical** - the stack costs ~$0.76/hour.

**What we did:**
```bash
cd infra/
./delete-full-stack.sh --stack-name openai-sagemaker-stack --region eu-north-1
```

**Resources deleted (in order):**
1. CloudFormation stack (triggers deletion of all nested resources)
2. SageMaker endpoint, endpoint config, and model
3. Lambda function
4. API Gateway HTTP API
5. EC2 instance and Elastic IP
6. Security group
7. IAM roles and instance profile
8. S3 bucket and all objects

**Duration:** ~5-10 minutes (SageMaker endpoint deletion is slowest)

**Notes:**
- Use `--keep-s3` flag if you want to preserve the S3 bucket for faster redeployment
- The script waits for stack deletion to complete before exiting
- If deletion fails, check CloudFormation console for stuck resources

---

## Step 10: Verify Cleanup

**Purpose:** Confirm all resources are deleted and no ongoing charges.

**What we did:**

### Verify CloudFormation Stack Deleted
```bash
aws cloudformation describe-stacks --region eu-north-1 \
  --stack-name openai-sagemaker-stack 2>&1 | grep -q "does not exist" && echo "✓ Stack deleted"
```

### Verify SageMaker Resources Deleted
```bash
# Check endpoints
aws sagemaker list-endpoints --region eu-north-1 \
  --query 'Endpoints[?contains(EndpointName, `openai-sagemaker-stack`)]'

# Check endpoint configs
aws sagemaker list-endpoint-configs --region eu-north-1 \
  --query 'EndpointConfigs[?contains(EndpointConfigName, `openai-sagemaker-stack`)]'

# Check models
aws sagemaker list-models --region eu-north-1 \
  --query 'Models[?contains(ModelName, `openai-sagemaker-stack`)]'
```

**Expected:** Empty arrays `[]` for all queries.

### Verify EC2 Resources Deleted
```bash
aws ec2 describe-instances --region eu-north-1 \
  --filters "Name=tag:Name,Values=*openai-sagemaker-stack*" \
  --query 'Reservations[*].Instances[?State.Name!=`terminated`].[InstanceId,State.Name]'
```

**Expected:** Empty array `[]` (or only terminated instances).

### Verify S3 Bucket Deleted
```bash
aws s3api head-bucket --bucket openai-sagemaker-stack-lambda-753916465480-eu-north-1 2>&1 \
  | grep -q "404" && echo "✓ Bucket deleted"
```

### Verify Lambda Functions Deleted
```bash
aws lambda list-functions --region eu-north-1 \
  --query 'Functions[?contains(FunctionName, `openai-sagemaker-stack`)]'
```

**Expected:** Empty array `[]`.

### Verify API Gateways Deleted
```bash
aws apigatewayv2 get-apis --region eu-north-1 \
  --query 'Items[?contains(Name, `openai-sagemaker-stack`)]'
```

**Expected:** Empty array `[]`.

**All resources confirmed deleted = No ongoing charges.**

---

## Quick Reference Commands

### Full Deployment (Automated)
```bash
cd infra/
./deploy-full-stack.sh --vpc-id vpc-xxx --subnet-id subnet-xxx
```

### Manual Step-by-Step
```bash
# 1. Check credentials
aws sts get-caller-identity

# 2. Package Lambda
rm -rf .build && mkdir -p .build/package
uv pip install --target .build/package boto3 --quiet
cp -r lambda/openai-proxy/src/* .build/package/
cd .build/package && zip -r ../lambda-openai-proxy.zip . -q && cd -

# 3. Create S3 bucket and upload
STACK_NAME="openai-sagemaker-stack"
REGION="eu-north-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
LAMBDA_S3_BUCKET="${STACK_NAME}-lambda-${AWS_ACCOUNT_ID}-${REGION}"

aws s3api create-bucket --bucket "$LAMBDA_S3_BUCKET" --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION"

aws s3 cp .build/lambda-openai-proxy.zip "s3://$LAMBDA_S3_BUCKET/lambda/$STACK_NAME/lambda-openai-proxy.zip"
aws s3 cp openwebui/docker-compose.yml "s3://$LAMBDA_S3_BUCKET/openwebui/docker-compose.yml"
aws s3 cp openwebui/setup.sh "s3://$LAMBDA_S3_BUCKET/openwebui/setup.sh"

# 4. Deploy CloudFormation
aws cloudformation deploy \
  --region "$REGION" \
  --stack-name "$STACK_NAME" \
  --template-file infra/full-stack.yaml \
  --parameter-overrides \
    HuggingFaceModelId="distilgpt2" \
    SageMakerInstanceType="ml.g4dn.xlarge" \
    EC2InstanceType="t3.small" \
    VpcId="vpc-xxx" \
    SubnetId="subnet-xxx" \
    LambdaS3Bucket="$LAMBDA_S3_BUCKET" \
    LambdaS3Key="lambda/$STACK_NAME/lambda-openai-proxy.zip" \
  --capabilities CAPABILITY_NAMED_IAM

# 5. Get outputs
aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK_NAME" \
  --query 'Stacks[0].Outputs' --output table
```

### Cleanup
```bash
cd infra/
./delete-full-stack.sh --stack-name openai-sagemaker-stack --region eu-north-1
```
