# sample-nodejs-devops

A lightweight Node.js application with a full DevSecOps pipeline — SAST, image scanning, version bumping, Docker Hub publishing, and GitOps deployment via ArgoCD.

**Companion repo:** [AviAtia/devops-infra](https://github.com/AviAtia/devops-infra) — Helm chart, Jenkins setup, and shared CI scripts  
**Docker Hub:** [avrahamatia/sample-nodejs](https://hub.docker.com/r/avrahamatia/sample-nodejs)

---

## Application

Built with Express.js and runs on port `8080` (configurable via `PORT` env var).

| Endpoint | Description |
|---|---|
| `GET /my-app` | Main endpoint — returns `Hello, World!` |
| `GET /about` | App description |
| `GET /ready` | Readiness probe |
| `GET /live` | Liveness probe |
| `GET /metrics` | Prometheus metrics |

### Run locally

```bash
npm install
node app.js
curl http://localhost:8080/my-app
```

### Run with Docker

```bash
docker build -t sample-nodejs .
docker run -p 8080:8080 sample-nodejs
```

---

## Repository structure

```
sample-nodejs-devops/
├── app.js                   # Express app
├── package.json
├── Dockerfile               # Multi-stage Alpine build, non-root user
├── .dockerignore
└── ci/
    ├── Jenkinsfile          # PR gated pipeline
    └── Jenkinsfile.main     # Post-merge pipeline
```

> CI scripts (SAST, Trivy, Docker build/push, version bump, Helm update) live in
> [AviAtia/devops-infra/ci-scripts/](https://github.com/AviAtia/devops-infra/tree/main/ci-scripts)
> and are cloned into the workspace at the start of each pipeline run.

---

## CI/CD pipelines

Both pipelines clone `devops-infra` at the start of each run to pull in the shared CI scripts:

```groovy
stage('Checkout') {
    steps {
        checkout scm
        sh "git clone https://github.com/AviAtia/devops-infra.git devops-infra"
    }
}
```

### PR gated pipeline (`ci/Jenkinsfile`)

Runs on every pull request. The GitHub merge button is blocked until all checks pass.

| Stage | Tool | Fails on |
|---|---|---|
| SAST | Semgrep (Docker) | ERROR severity findings |
| Docker Build | Docker | Build errors |
| Trivy Scan | Trivy | HIGH / CRITICAL CVEs with available fixes |

Jenkins posts a status check (`Jenkins CI/PR`) back to the PR via `githubNotify`. Branch protection on `main` requires this check to pass.

### Post-merge pipeline (`ci/Jenkinsfile.main`)

Triggers on every commit to `main`. Skips commits whose message starts with `[version bump]` to prevent infinite loops.

| Stage | What it does |
|---|---|
| Skip Check | Aborts if this is a version bump commit |
| Version Bump | Increments patch version in `package.json`, commits back to main with `[version bump]` prefix |
| Docker Build | Builds image tagged with the new semver version |
| Trivy Scan | Blocks push if fixable HIGH/CRITICAL CVEs found |
| Push to Docker Hub | Pushes `avrahamatia/sample-nodejs:<version>` and `:latest` |
| Update Helm Chart | Clones devops-infra, updates `values.yaml` image tag, pushes — ArgoCD auto-deploys |

---

## Dockerfile

Multi-stage Alpine build:

1. **`deps` stage** — installs only production npm dependencies
2. **`runner` stage** — copies deps, upgrades OS packages for CVE fixes, runs as non-root user

```dockerfile
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

FROM node:20-alpine AS runner
WORKDIR /app
RUN apk upgrade --no-cache libcrypto3 libssl3
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=deps /app/node_modules ./node_modules
COPY app.js .
RUN chown -R appuser:appgroup /app
USER appuser
ENV PORT=8080
EXPOSE 8080
CMD ["node", "app.js"]
```

---

## Security

- **SAST** — Semgrep scans all source files on every PR
- **Trivy** — scans the built Docker image before any push to Docker Hub; fails on HIGH/CRITICAL with available fixes (`--ignore-unfixed` is the default, configurable as a Jenkins parameter)
- **Non-root container** — app runs as a dedicated `appuser` with no write access outside `/app`
- **Branch protection** — `main` requires the Jenkins status check to pass; direct pushes are blocked

---

## Jenkins credentials required

| ID | Type | Used for |
|---|---|---|
| `dockerhub-credentials` | Username/Password | Push image to Docker Hub |
| `github-credentials` | Username/Password (PAT) | Version bump commit + Helm chart update |

Configure these in Jenkins → Manage Jenkins → Credentials.
