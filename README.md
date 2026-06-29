# DevSecOps Pipeline

A reference CI/CD security pipeline demonstrating automated vulnerability scanning at every layer of the software supply chain. Uses a deliberately vulnerable Flask app as the scan target.

## Project Structure

| File | Purpose |
|---|---|
| `app/app.py` | The scan target — a deliberately vulnerable Flask app with SQLi, hardcoded secrets, and debug mode enabled |
| `app/requirements.txt` | Python dependencies; `requests==2.28.0` is intentionally pinned to a vulnerable version to trigger SCA scanners |
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

SAST, secret scanning, and SCA run on every push to `master` and on pull requests. DAST runs on a weekly schedule and on-demand via `workflow_dispatch` — it requires a live app and is too slow and environment-dependent to gate every commit.

> **Expected demo result:** The Trivy job fails while the intentionally vulnerable dependency pins remain. This means the configured HIGH/CRITICAL gate detected findings; it does not mean the scanner crashed. Open the workflow run's **Summary**, then download **trivy-reports** under **Artifacts** to review the JSON findings.

---

## Tools

Each workflow file has inline comments showing how to tune that scanner (severity gates, suppressions, custom rules) — start there when you want to change behavior.

### Semgrep (SAST)
Static application security testing — analyzes source code without running it. Catches injection flaws, insecure patterns, and secrets embedded in code.

This pipeline uses three Semgrep rule sets:
- `p/python` — Python-specific security patterns
- `p/secrets` — Hardcoded credentials and API keys
- `p/owasp-top-ten` — Coverage of the OWASP Top 10

Results are uploaded to GitHub Security (Code Scanning) as SARIF.

### Gitleaks (Secret Scanning)
Scans the full git history for secrets that were committed and later removed — a pattern that Semgrep misses because Semgrep only sees the current working tree. Catches API keys, tokens, passwords, and private keys using 150+ regex patterns.

Runs with `fetch-depth: 0` to pull complete history. Fails the job immediately when any secret is found. Findings appear in GitHub Security via SARIF upload.

### Trivy (SCA — dependencies + container)
Software composition analysis against the NVD vulnerability database. Runs two scans:

1. **Filesystem scan** — checks `app/requirements.txt` against known CVEs
2. **Image scan** — builds the Docker image and scans installed OS packages and Python deps inside it

The image scan catches vulnerabilities that come from the base image (e.g., `python:3.11-slim`) that would not appear in `requirements.txt`. Both scans fail on HIGH or CRITICAL severity findings.

### OWASP ZAP (DAST)
Dynamic application security testing — scans the running app over HTTP rather than analyzing source code. Catches runtime vulnerabilities that static analysis misses: active SQL injection, reflected XSS, missing security headers, and insecure server configuration.

The workflow starts the app via `docker compose`, waits for the `/health` endpoint to respond, then runs ZAP's API scan mode against [`app/openapi.yaml`](app/openapi.yaml). The spec enumerates all endpoints and parameters, giving ZAP precise targets rather than relying on crawling.

DAST is intentionally not triggered on every push — it requires a running environment and takes several minutes. A weekly scheduled run plus `workflow_dispatch` for on-demand scans is the right cadence for a pre-production-style gate.

---

## Required Secrets

No secrets need to be configured. `GITHUB_TOKEN` is provided automatically by GitHub Actions.

---

## Local Development

Requires: Docker, `make`

```bash
# Start the demo app
make run

# Run all scanners locally (requires semgrep, trivy installed)
make sast
make sca

# Tear down
make stop
```

See the [Makefile](Makefile) for all available targets.

---

## Demo App

[`app/app.py`](app/app.py) is intentionally vulnerable. It exists to demonstrate that each scanner fires on real findings:

- **Hardcoded secrets** → triggers Semgrep (`p/secrets` ruleset) + Gitleaks (`generic-api-key` rule — the secret values are deliberately high-entropy so Gitleaks' entropy threshold is actually met)
- **SQL injection via f-string** → triggers Semgrep (`p/python` ruleset, static) + ZAP active scan (runtime)
- **`debug=True`** → triggers Semgrep (`p/python` ruleset)
- **`requests==2.28.0`** (CVE-2023-32681) → detected by Trivy, but its CVSS (6.1, MEDIUM) is below the HIGH/CRITICAL gate. It shows up in scan output without failing the build — a deliberate example of "detected" vs. "gated." The SCA job currently *does* fail, but because of HIGH-severity CVEs in the pinned Flask/Werkzeug versions (CVE-2023-30861, CVE-2024-34069 — see [requirements.txt](app/requirements.txt)), not because of this one.

Do not deploy this app to any environment other than local development.
