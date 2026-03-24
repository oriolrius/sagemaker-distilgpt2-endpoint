# OpenWebUI

Web-based chat interface for the SageMaker vLLM endpoint.

## Quick Start

### Local Setup

```bash
cd openwebui/

# Copy and configure environment
cp .env.example .env
# Edit .env and set OPENAI_API_BASE_URL to your API Gateway URL

# Run setup (installs Docker if needed)
./setup.sh

# Or manually with docker-compose
docker-compose up -d
```

### Access

- **URL**: http://localhost (or http://localhost:80)
- **Authentication**: Disabled by default

### Configuration

Edit `.env` file:

| Variable | Description | Default |
|----------|-------------|---------|
| `OPENAI_API_BASE_URL` | API Gateway endpoint URL | Required |
| `OPENAI_API_KEY` | API key (not needed for this setup) | `not-required` |
| `OPENWEBUI_PORT` | Port to expose | `80` |
| `WEBUI_AUTH` | Enable authentication | `false` |

### Commands

```bash
# Start
docker-compose up -d

# Stop
docker-compose down

# View logs
docker-compose logs -f

# Restart
docker-compose restart
```

## Data Persistence

Data is stored in `./data/` directory:
- SQLite database (users, chats, settings)
- Uploaded files

## CloudFormation Integration

In production, OpenWebUI runs on ECS Fargate. The CloudFormation template (`infra/full-stack.yaml`) defines a Fargate task that pulls the OpenWebUI image directly. These local files (`docker-compose.yml`, `setup.sh`) are for local development only.

## Production Notes

For production use:

1. Enable authentication:
   ```
   WEBUI_AUTH=true
   ```

2. Use HTTPS with a custom domain and SSL certificate

3. Consider using EFS for data persistence across instances
