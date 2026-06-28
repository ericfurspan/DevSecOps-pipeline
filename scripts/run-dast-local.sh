#!/usr/bin/env bash
# Local equivalent of .github/workflows/dast.yml — runs ZAP's API scan
# against the locally running app, using host.docker.internal to override
# the spec's server URL since Docker Desktop (macOS/Windows) can't reach
# the host via --network=host the way the GitHub Actions runner can.
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p reports

echo "Starting target app..."
docker compose up -d

cleanup() {
  echo "Tearing down target app..."
  docker compose down
}
trap cleanup EXIT

echo "Waiting for /health..."
for i in $(seq 1 12); do
  if curl -sf http://localhost:5001/health > /dev/null; then
    echo "App is up."
    break
  fi
  if [ "$i" -eq 12 ]; then
    echo "App did not become healthy in time." >&2
    exit 1
  fi
  sleep 5
done

echo "Running ZAP API scan..."
docker run --rm \
  --add-host=host.docker.internal:host-gateway \
  -v "$(pwd)/app:/zap/wrk/app:ro" \
  -v "$(pwd)/reports:/zap/wrk/reports" \
  -t ghcr.io/zaproxy/zaproxy:stable \
  zap-api-scan.py \
    -t /zap/wrk/app/openapi.yaml \
    -f openapi \
    -O http://host.docker.internal:5001 \
    -J reports/zap-report.json \
    -r reports/zap-report.html \
    -I

echo "ZAP report: reports/zap-report.html"
