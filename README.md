# DevSecOps Pipeline

A reference CI/CD security pipeline demonstrating automated vulnerability scanning at every layer of the software supply chain. Uses a deliberately vulnerable Flask app as the scan target.

## Project Structure

| File | Purpose |
|---|---|
| `app/app.py` | The scan target — a deliberately vulnerable Flask app with SQLi, hardcoded secrets, and debug mode enabled |
| `app/requirements.txt` | Python dependencies; `requests==2.28.0` is intentionally pinned to a vulnerable version to trigger SCA scanners |
| `app/openapi.yaml` | OpenAPI 3.0 spec for the demo app — used by the ZAP API scan to enumerate endpoints |
| `.semgrep/custom-rules.yml` | Three custom Semgrep rules that match the exact vulnerabilities in `app.py` |
| `.github/workflows/sast.yml` | CI workflow: runs Semgrep SAST, uploads SARIF to GitHub Security |
| `.github/workflows/secrets.yml` | CI workflow: runs Gitleaks across the full git history to catch secrets ever committed |
| `.github/workflows/sca.yml` | CI workflow: runs Trivy (deps + container image) and OWASP Dependency-Check in parallel |
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
| `sca.yml` (job: trivy) | Trivy | Python deps + Docker image | HIGH or CRITICAL CVE | push to `master`, PRs |
| `sca.yml` (job: dependency-check) | OWASP Dependency-Check | Python deps (NVD database) | CVSS score ≥ 7.0 | push to `master`, PRs |
| `dast.yml` | OWASP ZAP | Running app (HTTP) | Any high-severity finding | Weekly (Sundays), manual |

SAST, secret scanning, and SCA run on every push to `master` and on pull requests. DAST runs on a weekly schedule and on-demand via `workflow_dispatch` — it requires a live app and is too slow and environment-dependent to gate every commit.

---

## Tools

Each workflow file has inline comments showing how to tune that scanner (severity gates, suppressions, custom rules) — start there when you want to change behavior.

### Semgrep (SAST)
Static application security testing — analyzes source code without running it. Catches injection flaws, insecure patterns, and secrets embedded in code.

This pipeline uses three Semgrep rule sets:
- `p/python` — Python-specific security patterns
- `p/secrets` — Hardcoded credentials and API keys
- `p/owasp-top-ten` — Coverage of the OWASP Top 10

Plus three custom rules in [`.semgrep/custom-rules.yml`](.semgrep/custom-rules.yml):
- `hardcoded-secret-variable` — Variables named `SECRET`, `PASSWORD`, `API_KEY`, or `TOKEN` assigned a literal string
- `sql-injection-fstring-execute` — SQL queries built with f-strings passed to `.execute()`
- `flask-debug-true` — `app.run(debug=True)` left in code

Results are uploaded to GitHub Security (Code Scanning) as SARIF.

### Gitleaks (Secret Scanning)
Scans the full git history for secrets that were committed and later removed — a pattern that Semgrep misses because Semgrep only sees the current working tree. Catches API keys, tokens, passwords, and private keys using 150+ regex patterns.

Runs with `fetch-depth: 0` to pull complete history. Fails the job immediately when any secret is found. Findings appear in GitHub Security via SARIF upload.

`GITLEAKS_LICENSE` is required for scanning private repos in GitHub organizations; it is not required for personal repos.

### Trivy (SCA — dependencies + container)
Software composition analysis against the NVD vulnerability database. Runs two scans:

1. **Filesystem scan** — checks `app/requirements.txt` against known CVEs
2. **Image scan** — builds the Docker image and scans installed OS packages and Python deps inside it

The image scan catches vulnerabilities that come from the base image (e.g., `python:3.11-slim`) that would not appear in `requirements.txt`. Both scans fail on HIGH or CRITICAL severity findings.

### OWASP Dependency-Check (SCA — NVD deep scan)
A complementary SCA tool that cross-references dependencies against the NVD, using CPE matching and additional heuristics. Runs alongside Trivy because the two tools use different matching strategies and catch different CVE subsets.

Fails the job when any dependency has a CVSS score ≥ 7.0. Outputs HTML and XML reports. The HTML report is retained as a GitHub Actions artifact for 30 days.

`NVD_API_KEY` is optional but strongly recommended — without it, NVD rate-limits the database download and the scan can take 30+ minutes.

### OWASP ZAP (DAST)
Dynamic application security testing — scans the running app over HTTP rather than analyzing source code. Catches runtime vulnerabilities that static analysis misses: active SQL injection, reflected XSS, missing security headers, and insecure server configuration.

The workflow starts the app via `docker compose`, waits for the `/health` endpoint to respond, then runs ZAP's API scan mode against [`app/openapi.yaml`](app/openapi.yaml). The spec enumerates all endpoints and parameters, giving ZAP precise targets rather than relying on crawling.

DAST is intentionally not triggered on every push — it requires a running environment and takes several minutes. A weekly scheduled run plus `workflow_dispatch` for on-demand scans is the right cadence for a pre-production-style gate.

---

## Required Secrets

Configure these in **GitHub → Settings → Secrets and variables → Actions**.

| Secret | Required by | Notes |
|---|---|---|
| `SEMGREP_APP_TOKEN` | `sast.yml` | From [semgrep.dev](https://semgrep.dev). Without it, Semgrep runs in CI mode with no cloud features — still blocks on findings. |
| `GITLEAKS_LICENSE` | `secrets.yml` | Only required for GitHub organization repos. Not needed for personal repos. |
| `NVD_API_KEY` | `sca.yml` (dependency-check job) | Optional but speeds up NVD database download significantly. Get one at [nvd.nist.gov/developers/request-an-api-key](https://nvd.nist.gov/developers/request-an-api-key). |

`GITHUB_TOKEN` is provided automatically by GitHub Actions — no configuration needed.

---

## Local Development

Requires: Docker, `make`

```bash
# Start the demo app
make run

# Run all scanners locally (requires semgrep, trivy installed)
make sast
make sca
make dast

# Tear down
make stop
```

See the [Makefile](Makefile) for all available targets.

---

## Demo App

[`app/app.py`](app/app.py) is intentionally vulnerable. It exists to demonstrate that each scanner fires on real findings:

- **Hardcoded secrets** → triggers Semgrep `hardcoded-secret-variable` + Gitleaks (`generic-api-key` rule — verified both fire; the secret values are deliberately high-entropy so Gitleaks' entropy threshold is actually met)
- **SQL injection via f-string** → triggers Semgrep `sql-injection-fstring-execute` (static) + ZAP active scan (runtime)
- **`debug=True`** → triggers Semgrep `flask-debug-true`
- **`requests==2.28.0`** (CVE-2023-32681) → detected by Trivy + OWASP Dependency-Check, but its CVSS (6.1, MEDIUM) is below both tools' failure gate (HIGH/CRITICAL, CVSS ≥ 7.0). It shows up in scan output without failing the build — a real example of "detected" vs. "gated." The SCA jobs currently *do* fail, but because of HIGH-severity CVEs in the pinned Flask/Werkzeug versions (CVE-2023-30861, CVE-2024-34069 — see [requirements.txt](app/requirements.txt)), not because of this one.

Do not deploy this app to any environment other than local development.
