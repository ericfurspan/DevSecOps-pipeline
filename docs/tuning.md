# Configuration & Tuning

This is a reference for adjusting how each scanner behaves — what to suppress, what severity to gate on, and how to write or modify rules. For *what* each tool scans and *when* it runs, see the [README](../README.md).

---

## Semgrep (SAST) — [sast.yml](../.github/workflows/sast.yml)

**Rule sources in use**: `p/python`, `p/secrets`, `p/owasp-top-ten` (Semgrep Registry rulesets) plus the custom rules in [.semgrep/custom-rules.yml](../.semgrep/custom-rules.yml).

| Want to... | How |
|---|---|
| Write a new custom rule | Add a rule block to `.semgrep/custom-rules.yml`. Each rule needs `id`, `pattern` (or `patterns`), `message`, `languages`, `severity`. |
| Change a finding's severity | Edit the `severity` field on the rule (`ERROR`, `WARNING`, `INFO`). Only `ERROR`/`WARNING` typically fail CI depending on `--severity` filtering. |
| Suppress a specific finding inline | Add `# nosemgrep: <rule-id>` as a comment on the offending line. |
| Ignore whole files/paths | Add a `.semgrepignore` file at the repo root (same syntax as `.gitignore`). |
| Add/remove a registry ruleset | Add/remove a `--config p/<ruleset>` line in `sast.yml`. Browse available rulesets at the Semgrep Registry. |
| Test a rule against test code | `semgrep --config .semgrep/custom-rules.yml --test` (requires matching `<rule-id>.py` test fixtures with `# ruleid:`/`# ok:` annotations). |

Docs: [Semgrep rule syntax](https://semgrep.dev/docs/writing-rules/rule-syntax/) · [Ignoring findings](https://semgrep.dev/docs/ignoring-files-folders-code/) · [Rule Registry](https://semgrep.dev/explore)

---

## Gitleaks (Secret Scanning) — [secrets.yml](../.github/workflows/secrets.yml)

**Currently**: runs with Gitleaks' built-in default rules (150+ secret patterns), no local config file.

| Want to... | How |
|---|---|
| Allowlist a known false positive | Add a `.gitleaks.toml` at the repo root with an `[allowlist]` block (by regex, path, or commit SHA), then reference it via the action's `config-path` input or `GITLEAKS_CONFIG` env var. |
| Add a custom detection rule | Add a `[[rules]]` block to `.gitleaks.toml` with a `regex` and `id`. |
| Scan only a subset of history | Adjust `fetch-depth` in the `actions/checkout` step (currently `0` = full history). |

Docs: [Gitleaks configuration](https://github.com/gitleaks/gitleaks#configuration) · [Default rule list](https://github.com/gitleaks/gitleaks/blob/master/config/gitleaks.toml)

---

## Trivy (SCA — deps + container) — [sca.yml](../.github/workflows/sca.yml)

**Currently**: gates on `HIGH,CRITICAL` severity, no ignore file.

| Want to... | How |
|---|---|
| Change the severity gate | Edit the `severity:` input in the `aquasecurity/trivy-action` steps (e.g. add `MEDIUM`). |
| Suppress a specific CVE | Add a `.trivyignore` file at the repo root with one CVE ID per line (e.g. `CVE-2023-32681`), optionally with an expiry date. |
| Use a full config file instead of inline flags | Add `trivy.yaml` and pass `--config trivy.yaml`; supports ignore lists, severity, scanners, and more in one place. |
| Scan additional targets (e.g. IaC, secrets) | Add `scan-type: config` or `scan-type: secret` as additional steps. |

Docs: [Trivy configuration](https://aquasecurity.github.io/trivy/latest/docs/configuration/) · [Filtering by severity/ignoring](https://aquasecurity.github.io/trivy/latest/docs/configuration/filtering/)

---

## OWASP Dependency-Check (SCA — NVD deep scan) — [sca.yml](../.github/workflows/sca.yml)

**Currently**: fails on `--failOnCVSS 7`, no suppression file.

| Want to... | How |
|---|---|
| Change the CVSS failure threshold | Edit `--failOnCVSS` in the `args` input (e.g. `--failOnCVSS 9` to only fail on critical). |
| Suppress a specific finding | Create a `suppression.xml` file with a `<suppress>` block matching the CVE/CPE, then add `--suppression suppression.xml` to `args`. |
| Speed up the NVD database download | Set the `NVD_API_KEY` secret (see README's Required Secrets table) — without it, scans can take 30+ minutes due to rate limiting. |
| Scan additional package ecosystems | Dependency-Check auto-detects manifests (e.g. `package.json`, `pom.xml`) under `path:` — no extra config needed if present. |

Docs: [Suppressing false positives](https://jeremylong.github.io/DependencyCheck/general/suppression.html) · [CLI arguments reference](https://jeremylong.github.io/DependencyCheck/dependency-check-cli/arguments.html)

---

## OWASP ZAP (DAST) — [dast.yml](../.github/workflows/dast.yml)

**Currently**: runs the API scan add-on against [app/openapi.yaml](../app/openapi.yaml) with default alert thresholds, no scan policy or context file.

| Want to... | How |
|---|---|
| Change which alerts fail the build | Add a `-c` config file or inline rule overrides (e.g. `10021:IGNORE`) via `cmd_options`, or pass a custom `rules.tsv` (one rule ID + threshold per line) via the action's `rules_file_name` input. |
| Scan a different target or add auth | Edit `target:` (URL, OpenAPI/SOAP file, or GraphQL schema) and `format:`; for authenticated scans, add a ZAP context file via `-n`. |
| Run a fuller scan instead of just the API definition | Swap `zaproxy/action-api-scan` for `zaproxy/action-full-scan` (adds active spidering) — slower, more thorough. |
| Tune scan duration/aggressiveness | Add `-z "-config scanner.threadPerHost=5"` or similar `-z` passthrough options to `cmd_options`. |

Docs: [ZAP Docker automation](https://www.zaproxy.org/docs/docker/api-scan/) · [Alert filters / rules](https://www.zaproxy.org/docs/desktop/addons/alert-filters/) · [action-api-scan inputs](https://github.com/zaproxy/action-api-scan)

---

## General workflow

1. Make a config change (rule file, ignore file, severity flag).
2. Run the matching `make` target locally first (`make sast`, `make sca`, `make dast`) to see the effect before pushing.
3. Push to a branch/PR — SAST, secrets, and SCA run automatically; trigger DAST manually via **Actions → DAST — OWASP ZAP → Run workflow** if you need an immediate check rather than waiting for the weekly schedule.
