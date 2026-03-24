# CLAUDE.md

AWS deployment stack for running HuggingFace LLMs on SageMaker with an OpenAI-compatible API and OpenWebUI chat interface. All resources managed via a single CloudFormation stack.

## Rules

1. **Region:** Always `eu-west-1` (Ireland). No exceptions.
2. **Credentials:** Never commit. Use `/aws-sandbox-credentials` (lease: `cloud-solutions`) to refresh.
3. **Package manager:** `uv`, never pip.
4. **Test first:** `cd lambda/openai-proxy && uv run pytest -v` before any deployment.
5. **CloudFormation only:** Never create AWS resources manually.
6. **Cleanup:** Always delete stacks when done (~$0.80/hr).
7. **Commits:** Conventional Commits, validated by `.githooks/commit-msg`.
8. **Linting:** `uv run ruff check` and `uv run ruff format` before committing.

## Architecture

```
Browser → OpenWebUI (ECS Fargate :8080) → API Gateway (HTTPS) → Lambda (OpenAI Proxy) → SageMaker (vLLM, GPU)
                                          ↑
curl/SDK ─────────────────────────────────┘
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed diagrams.

## Conventions

- **Python:** 3.11+, Ruff (120 char lines), PEP 8
- **Commits:** Conventional Commits via Commitizen (`git config core.hooksPath .githooks`)
- **Testing:** pytest + moto (AWS mocking)
- **Sub-projects:** `lambda/openai-proxy/` and `scripts/` each have their own `pyproject.toml`

## Quick Reference

```bash
# Credentials
/aws-sandbox-credentials          # Fetch from Innovation Sandbox

# Lambda dev
cd lambda/openai-proxy && uv sync --dev && uv run pytest -v

# Deploy
cd infra && ./deploy-full-stack.sh --vpc-id vpc-xxx --subnet-id subnet-xxx

# Cleanup
cd infra && ./delete-full-stack.sh --stack-name openai-sagemaker-stack --region eu-west-1

# Commits & releases
uvx --from commitizen cz commit   # Interactive conventional commit
uvx --from commitizen cz bump     # Bump version based on commits
```
