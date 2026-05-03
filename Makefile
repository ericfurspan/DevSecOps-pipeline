.PHONY: build run stop sast sca dast clean

IMAGE_NAME := devsecops-demo
TAG        := latest

build:
	docker build -t $(IMAGE_NAME):$(TAG) .

run: build
	docker compose up -d

stop:
	docker compose down

# SAST — Semgrep (requires `pip install semgrep`)
sast:
	@mkdir -p reports
	semgrep scan \
		--config p/python \
		--config p/secrets \
		--sarif \
		--output reports/semgrep.sarif \
		app/
	@echo "SAST report: reports/semgrep.sarif"

# SCA — Trivy (requires `brew install trivy` or Docker)
sca:
	@mkdir -p reports
	trivy fs app/ \
		--format json \
		--output reports/trivy-fs.json \
		--severity MEDIUM,HIGH,CRITICAL
	@echo "SCA report: reports/trivy-fs.json"

# DAST — ZAP via Docker
dast:
	bash scripts/run-dast-local.sh

clean:
	docker compose down --rmi local --volumes --remove-orphans
	rm -f reports/*.json reports/*.sarif reports/*.html
