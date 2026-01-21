# flux-marketplace-docker

Monorepo for Flux Marketplace / FluxOS-friendly Docker images.

## Layout

- `Gaming/<project>/` → one Docker image (with its own `Dockerfile`, `README.md`, and optional `flux-spec.json`)
- `AI/<project>/` → one Docker image for AI / automation tooling
- `Infrastructure/<project>/` → infrastructure/support images
- `Blockchain/<project>/` → (reserved) blockchain-related images

## Local builds

Build from repo root by pointing Docker at the project directory:

```bash
docker build -t <name>:local ./Gaming/<project>
```

## CI

Each project has a dedicated GitHub Actions workflow that:

- builds on PRs and pushes,
- pushes images to GHCR on `main` (and on manual dispatch for versioned tags),
- only triggers when files under that project folder change.

Optional: if you add repo secret `DOCKERHUB_TOKEN`, workflows also push to Docker Hub under `littlestache/*`.
