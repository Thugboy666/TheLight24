#!/usr/bin/env bash
set -euo pipefail

ADMIN_TOKEN="${ADMIN_TOKEN:-}"
CUSTOMER_ID="${CUSTOMER_ID:-}"

if [[ -z "${ADMIN_TOKEN}" || -z "${CUSTOMER_ID}" ]]; then
  echo "Errore: imposta ADMIN_TOKEN e CUSTOMER_ID per il test analytics." >&2
  echo "Esempio: ADMIN_TOKEN=... CUSTOMER_ID=123 ./scripts/smoke_test.sh" >&2
  exit 1
fi

curl -fsS http://127.0.0.1:8080/system/health
curl -fsS http://127.0.0.1:8080/api/llm/health
curl -fsS -H "Content-Type: application/json" -d '{"prompt":"ping"}' http://127.0.0.1:8080/api/llm/chat | jq -r '.content'
curl -fsS -H "Authorization: Bearer ${ADMIN_TOKEN}" "http://127.0.0.1:8080/api/analytics/customer/${CUSTOMER_ID}" | jq
