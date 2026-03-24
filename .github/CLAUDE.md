# .github/

CI/CD workflows for GitHub Actions.

## Workflows

- **deploy.yml** — Manual trigger, 20min timeout. Package Lambda → S3 → CloudFormation → Get Fargate IP → Test.
- **destroy.yml** — Manual trigger, requires typing "DESTROY". Deletes CF stack + S3 bucket.

## Required Secrets

`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_REGION`, `VPC_ID`, `SUBNET_ID`
