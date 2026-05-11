# DevSecOps Pipeline

A reference CI/CD security pipeline demonstrating automated vulnerability scanning at every layer of the software supply chain. Uses a deliberately vulnerable Flask app as the scan target.

## Pipeline Overview

| Workflow | Tool | What it scans | Blocks on |
|---|---|---|---|
| `sast.yml` | Semgrep | Source code (SAST) | Any finding from configured rules |
| `secrets.yml` | Gitleaks | Git history + staged changes | Any secret found in repo history |
| `sca.yml` (job: trivy) | Trivy | Python deps + Docker image | HIGH or CRITICAL CVE |
| `sca.yml` (job: dependency-check) | OWASP Dependency-Check | Python deps (NVD database) | CVSS score ≥ 7.0 |

All workflows trigger on push to `main` and on pull requests.

---

## Tools

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

Fails the job when any dependency has a CVSS score ≥ 7.0. Outputs HTML (human-readable) and XML (for DefectDojo) reports. The HTML report is retained as a GitHub Actions artifact for 30 days.

`NVD_API_KEY` is optional but strongly recommended — without it, NVD rate-limits the database download and the scan can take 30+ minutes.

---

## Required Secrets

Configure these in **GitHub → Settings → Secrets and variables → Actions**.

| Secret | Required by | Notes |
|---|---|---|
| `SEMGREP_APP_TOKEN` | `sast.yml` | From [semgrep.dev](https://semgrep.dev). Without it, Semgrep runs in CI mode with no cloud features — still blocks on findings. |
| `GITLEAKS_LICENSE` | `secrets.yml` | Only required for GitHub organization repos. Not needed for personal repos. |
| `NVD_API_KEY` | `sca.yml` (dependency-check job) | Optional but speeds up NVD database download significantly. Get one at [nvd.nist.gov/developers/request-an-api-key](https://nvd.nist.gov/developers/request-an-api-key). |
| `DEFECTDOJO_URL` | All workflows | Base URL of your DefectDojo instance, e.g. `https://defectdojo.example.com`. Optional — skip DefectDojo upload steps if not using it. |
| `DEFECTDOJO_API_KEY` | All workflows | DefectDojo API v2 key. |
| `DEFECTDOJO_ENGAGEMENT_ID` | All workflows | The engagement ID to attach findings to. |

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

- **Hardcoded secrets** → triggers Semgrep `hardcoded-secret-variable` + Gitleaks
- **SQL injection via f-string** → triggers Semgrep `sql-injection-fstring-execute`
- **`debug=True`** → triggers Semgrep `flask-debug-true`
- **`requests==2.28.0`** (CVE-2023-32681) → triggers Trivy + OWASP Dependency-Check

Do not deploy this app to any environment other than local development.

---

## Finding Management

All scanner results are uploaded to [DefectDojo](https://github.com/DefectDojo/django-DefectDojo) via [`scripts/upload-to-defectdojo.sh`](scripts/upload-to-defectdojo.sh). DefectDojo deduplicates findings across scans, tracks remediation status, and provides a unified view across all tools.

Supported scan types for import:

| Scanner arg | DefectDojo scan type |
|---|---|
| `semgrep` | `SARIF` |
| `trivy` | `Trivy Scan` |
| `gitleaks` | `Gitleaks Scan` |
| `dependency-check` | `Dependency Check Scan` |
| `zap` | `ZAP Scan` |
