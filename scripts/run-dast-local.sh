#!/usr/bin/env bash
# Run ZAP DAST scan locally against the docker-compose app
set -euo pipefail

TARGET="${TARGET_URL:-http://localhost:5001}"
REPORT_DIR="$(dirname "$0")/../reports"
mkdir -p "$REPORT_DIR"

echo "Starting app..."
docker compose up -d

echo "Waiting for /health ..."
for i in $(seq 1 12); do
  curl -sf "${TARGET}/health" && break
  sleep 5
done

echo "Running ZAP baseline scan against ${TARGET} ..."
docker run --rm \
  --network host \
  -v "$(pwd)/reports:/zap/wrk" \
  ghcr.io/zaproxy/zaproxy:stable \
  zap-api-scan.py \
  -t "${TARGET}" \
  -f openapi \
  -J zap-report.json \
  -r zap-report.html \
  || true

echo "Report written to reports/zap-report.html"
docker compose down
