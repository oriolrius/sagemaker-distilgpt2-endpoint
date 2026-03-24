# openwebui/

Web-based chat interface. In production, runs on **ECS Fargate** (not EC2). These files are kept for **local development** only.

## Production (Fargate)

Defined in `infra/full-stack.yaml` — ECS task definition pulls `ghcr.io/open-webui/open-webui:main` directly. No ECR needed.

| Setting | Value |
|---------|-------|
| Image | `ghcr.io/open-webui/open-webui:main` |
| CPU / Memory | 0.5 vCPU / 1 GB |
| Port | 8080 (public IP, no ALB) |
| Auth | Disabled (`WEBUI_AUTH=false`) |
| Ollama | Disabled |
| Storage | Ephemeral (no EFS) |
| Logs | CloudWatch via awslogs driver |

The `OPENAI_API_BASE_URL` environment variable is set automatically by CloudFormation to the API Gateway endpoint.

## Local Development

```bash
cp .env.example .env
# Edit .env → set OPENAI_API_BASE_URL to your API Gateway URL
docker-compose up -d
# Access at http://localhost:80
```

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Local dev only — maps port 80→8080 |
| `setup.sh` | Legacy EC2 setup script (installs Docker + runs compose) |
| `.env.example` | Template for local config |
