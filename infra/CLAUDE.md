# infra/

CloudFormation IaC and deployment scripts for the full stack.

## Files

| File | Purpose |
|------|---------|
| `full-stack.yaml` | CloudFormation template (19 resources) |
| `deploy-full-stack.sh` | Package Lambda, upload to S3, deploy CF stack |
| `delete-full-stack.sh` | Delete CF stack and S3 bucket |

## CloudFormation Stack (19 resources)

- **SageMaker:** Model (DJL-LMI vLLM), EndpointConfig (ml.g4dn.xlarge), Endpoint
- **Lambda:** Function (Python 3.11), IAM Role (InvokeEndpoint), API GW Permission
- **API Gateway:** HTTP API, Stage, Integration, 3 Routes
- **ECS Fargate:** Cluster, TaskDefinition (0.5vCPU/1GB), Service, SecurityGroup (:8080), TaskExecutionRole, LogGroup
- **IAM:** 3 roles (SageMaker, Lambda, ECS)

## Parameters

| Parameter | Default | Required |
|-----------|---------|----------|
| `VpcId` | — | yes |
| `SubnetId` | — | yes (public) |
| `HuggingFaceModelId` | Qwen/Qwen2.5-1.5B-Instruct | no |
| `SageMakerInstanceType` | ml.g4dn.xlarge | no |
| `LambdaS3Bucket` | — | yes (auto-created by script) |
| `LambdaS3Key` | — | yes (auto-created by script) |

## Deploy

```bash
./deploy-full-stack.sh --vpc-id vpc-xxx --subnet-id subnet-xxx
```

Deployment takes ~7-10 minutes (SageMaker endpoint is the bottleneck).

The Fargate task's public IP is dynamic. The script discovers it automatically after deployment.

## Validate template

```bash
aws cloudformation validate-template --template-body file://full-stack.yaml --region eu-west-1
```
