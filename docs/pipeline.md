# DevSecOps Pipeline

Demo pipeline running SAST, SCA, and DAST against a deliberately vulnerable Flask app,
with findings uploaded to DefectDojo.

## Target App

| Endpoint | Purpose |
|---|---|
| `GET /health` | Liveness check |
| `GET /user?name=<name>` | **Vulnerable** — SQL injection via f-string |
| `GET /safe-user?name=<name>` | Safe — parameterized query |

The app also contains a hardcoded secret (`SECRET_API_KEY`) near the top of `app/app.py`.
Both issues are intentional for scanner demonstration.

## Scanners

| Tool | Type | Workflow |
|---|---|---|
| Semgrep | SAST | `.github/workflows/sast.yml` |
| Trivy | SCA | `.github/workflows/sca.yml` |
| OWASP ZAP | DAST | `.github/workflows/dast.yml` |

## Required GitHub Secrets

| Secret | Description |
|---|---|
| `SEMGREP_APP_TOKEN` | Semgrep Cloud token |
| `DEFECTDOJO_URL` | Base URL, e.g. `https://defectdojo.example.com` |
| `DEFECTDOJO_API_KEY` | DefectDojo API v2 key |
| `DEFECTDOJO_ENGAGEMENT_ID` | Engagement ID to attach all findings to |

## Local Usage

```bash
# Build and run the target app
make run

# Run all scanners locally (requires Docker)
make sast
make sca
make dast

# Upload a report manually
DEFECTDOJO_URL=... DEFECTDOJO_API_KEY=... DEFECTDOJO_ENGAGEMENT_ID=... \
  bash scripts/upload-to-defectdojo.sh semgrep reports/semgrep.sarif
```

## DefectDojo Setup

1. Deploy DefectDojo (docker compose or k8s — see DefectDojo docs)
2. Create a Product and Engagement
3. Note the Engagement ID from the URL: `/engagement/<ID>/`
4. Generate an API key under your user profile → API v2 Key
5. Add all secrets to GitHub → Settings → Secrets and variables → Actions
