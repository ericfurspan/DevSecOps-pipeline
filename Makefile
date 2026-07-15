.PHONY: build run stop sast sca clean

IMAGE_NAME := devsecops-demo
TAG        := latest

build:
	docker build -t $(IMAGE_NAME):$(TAG) .

run: build
	docker compose up -d

stop:
	docker compose down

# SAST — Semgrep (requires Semgrep 1.161.0 and jq)
# The vulnerable demo passes only when its exact reviewed finding set is unchanged.
sast:
	@mkdir -p reports
	@test "$$(semgrep --version --disable-version-check | head -n 1)" = "1.161.0" || \
		(echo "Semgrep 1.161.0 is required" >&2; exit 1)
	semgrep scan --config .semgrep/policy.yml --metrics off --disable-version-check \
		--no-rewrite-rule-ids --json --output reports/semgrep-raw.json app
	jq '[.results[] | {rule_id: .check_id, path: .path, start_line: .start.line}] \
		| sort_by(.rule_id, .path, .start_line)' reports/semgrep-raw.json > reports/semgrep-findings.json
	jq '[.[] | {rule_id: .rule_id, path: .path, start_line: .start_line}] \
		| sort_by(.rule_id, .path, .start_line)' .semgrep/expected-vulnerable.json > reports/semgrep-expected.json
	diff -u reports/semgrep-expected.json reports/semgrep-findings.json
	@rm reports/semgrep-expected.json
	@echo "Expected Semgrep findings verified."

# SCA — Trivy (requires `brew install trivy` or Docker)
# --severity here also includes MEDIUM (CI gates on HIGH,CRITICAL only) for a more thorough local look.
sca:
	@mkdir -p reports
	trivy fs app/ \
		--format json \
		--output reports/trivy-fs.json \
		--severity MEDIUM,HIGH,CRITICAL
	@echo "SCA report: reports/trivy-fs.json"

clean:
	docker compose down --rmi local --volumes --remove-orphans
	rm -f reports/*.json reports/*.sarif reports/*.html
