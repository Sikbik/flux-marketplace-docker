# n8n (Flux-friendly)

Custom n8n Docker image for Flux with automatic permission fixes.

## Build (local)

```bash
docker build -t n8n-flux:local ./AI/n8n
```

## CI

The repo workflow runs daily and only rebuilds/pushes when upstream `docker.n8n.io/n8nio/n8n:latest` changes.
