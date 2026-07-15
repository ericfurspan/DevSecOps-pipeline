# DevSecOps Pipeline

A reference CI/CD security pipeline demonstrating automated vulnerability scanning at every layer of the software supply chain. Uses a deliberately vulnerable Flask app as the scan target.

## Quick Start

**Prerequisites:** [Docker Desktop](https://www.docker.com/products/docker-desktop/), `make`

```bash
git clone https://github.com/ericfurspan/DevSecOps-pipeline.git
cd DevSecOps-pipeline
make run
```

The app starts at **http://localhost:5001**. Try `/health`, `/user?name=alice`, or `/safe-user?name=alice`.

To run scanners locally (requires `pip install semgrep` and `brew install trivy`):

```bash
make sast   # Semgrep SAST
make sca    # Trivy dependency scan
make stop   # Tear down the app
```

The CI pipeline runs automatically on every push to `master` and on pull requests — no secrets or configuration needed. DAST runs on a weekly schedule and via manual dispatch.

---

## Project Structure

| File | Purpose |
|---|---|
| `app/app.py` | The scan target — a deliberately vulnerable Flask app with SQLi, hardcoded secrets, and debug mode enabled |
| `app/requirements.txt` | Python dependencies; intentionally pinned to vulnerable versions to trigger SCA scanners |
| `app/openapi.yaml` | OpenAPI 3.0 spec for the demo app — used by the ZAP API scan to enumerate endpoints |
| `.github/workflows/sast.yml` | CI workflow: runs Semgrep SAST, uploads SARIF to GitHub Security |
| `.github/workflows/secrets.yml` | CI workflow: runs Gitleaks across the full git history to catch secrets ever committed |
| `.github/workflows/sca.yml` | CI workflow: runs Trivy against Python deps and the container image |
| `.github/workflows/dast.yml` | CI workflow: starts the app in Docker, runs OWASP ZAP API scan against it — weekly schedule + manual dispatch |
| `Dockerfile` | Builds the demo app container image from `python:3.11-slim` |
| `docker-compose.yml` | Runs the app locally; maps host port 5001 → container port 5000 |
| `Makefile` | Local dev shortcuts (`make run`, `make sast`, etc.) — not used by CI |

---

## Pipeline Overview

| Workflow | Tool | What it scans | Blocks on | Trigger |
|---|---|---|---|---|
| `sast.yml` | Semgrep | Source code (SAST) | Any finding from configured rules | push to `master`, PRs |
| `secrets.yml` | Gitleaks | Git history + staged changes | Any secret found in repo history | push to `master`, PRs |
| `sca.yml` | Trivy | Python deps + Docker image | HIGH or CRITICAL CVE | push to `master`, PRs |
| `dast.yml` | OWASP ZAP | Running app (HTTP) | Any high-severity finding | Weekly (Sundays), manual |

Each workflow file has inline comments explaining how to tune that scanner — severity gates, suppressions, and config options.

> **Expected demo result:** Semgrep and Trivy fail while the deliberately vulnerable source and dependency pins remain. These failures mean the configured security gates detected findings; they do not mean the scanners crashed. Trivy JSON findings are retained in the workflow run's **trivy-reports** artifact.

---

## Demo App

[`app/app.py`](app/app.py) is intentionally vulnerable. It exists to demonstrate that each scanner fires on real findings:

- **Hardcoded secrets** → triggers Semgrep (`p/secrets` ruleset) + Gitleaks (`generic-api-key` rule — the secret values are deliberately high-entropy so Gitleaks' entropy threshold is actually met)
- **SQL injection via f-string** → triggers Semgrep (`p/python` ruleset, static) + ZAP active scan (runtime)
- **`debug=True`** → triggers Semgrep (`p/python` ruleset)
- **`requests==2.28.0`** (CVE-2023-32681) → detected by Trivy, but its CVSS (6.1, MEDIUM) is below the HIGH/CRITICAL gate. It shows up in scan output without failing the build — a deliberate example of "detected" vs. "gated." The SCA job currently *does* fail, but because of HIGH-severity CVEs in the pinned Flask/Werkzeug versions (CVE-2023-30861, CVE-2024-34069 — see [requirements.txt](app/requirements.txt)), not because of this one.

Do not deploy this app to any environment other than local development.
