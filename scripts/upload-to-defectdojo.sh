#!/usr/bin/env bash
# Upload scan findings to DefectDojo via API
# Usage: upload-to-defectdojo.sh <scanner> <report-file>
#
# Required env vars:
#   DEFECTDOJO_URL           e.g. https://defectdojo.example.com
#   DEFECTDOJO_API_KEY       API v2 key
#   DEFECTDOJO_ENGAGEMENT_ID engagement ID to attach findings to

set -euo pipefail

SCANNER="${1:?Usage: $0 <scanner> <report-file>}"
REPORT="${2:?Usage: $0 <scanner> <report-file>}"

if [[ ! -f "$REPORT" ]]; then
  echo "ERROR: report file not found: $REPORT" >&2
  exit 1
fi

# Map scanner name → DefectDojo scan_type string
case "$SCANNER" in
  semgrep)           SCAN_TYPE="SARIF" ;;
  trivy)             SCAN_TYPE="Trivy Scan" ;;
  zap)               SCAN_TYPE="ZAP Scan" ;;
  gitleaks)          SCAN_TYPE="Gitleaks Scan" ;;
  dependency-check)  SCAN_TYPE="Dependency Check Scan" ;;
  *)
    echo "ERROR: unknown scanner '$SCANNER'. Add it to the case block." >&2
    exit 1
    ;;
esac

echo "Uploading $REPORT ($SCAN_TYPE) to DefectDojo engagement $DEFECTDOJO_ENGAGEMENT_ID ..."

curl -sf \
  -X POST \
  -H "Authorization: Token ${DEFECTDOJO_API_KEY}" \
  -F "engagement=${DEFECTDOJO_ENGAGEMENT_ID}" \
  -F "scan_type=${SCAN_TYPE}" \
  -F "file=@${REPORT}" \
  -F "active=true" \
  -F "verified=false" \
  -F "close_old_findings=false" \
  "${DEFECTDOJO_URL}/api/v2/import-scan/"

echo "Upload complete."
