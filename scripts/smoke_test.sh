#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://127.0.0.1:8080}"
ADMIN_TOKEN="${ADMIN_TOKEN:-}"

if [ -z "$ADMIN_TOKEN" ]; then
  echo "❌ ADMIN_TOKEN non impostato. Esempio: ADMIN_TOKEN=... $0"
  exit 1
fi

echo "→ /system/health"
HEALTH_CODE="$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/system/health" || true)"
if [ "$HEALTH_CODE" != "200" ]; then
  echo "❌ /system/health status=$HEALTH_CODE"
  exit 1
fi

echo "→ /admin/clients/all"
CLIENTS_JSON="$(curl -s -H "Authorization: Bearer $ADMIN_TOKEN" "$BASE_URL/admin/clients/all")"
CLIENT_ID="$(printf "%s" "$CLIENTS_JSON" | python3 -c 'import json,sys; data=json.load(sys.stdin); print((data.get("clients") or [{}])[0].get("id",""))')"
if [ -z "$CLIENT_ID" ]; then
  echo "❌ Nessun cliente trovato in /admin/clients/all"
  exit 1
fi

echo "→ /api/analytics/customer/$CLIENT_ID"
ANALYTICS_CODE="$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $ADMIN_TOKEN" \
  "$BASE_URL/api/analytics/customer/$CLIENT_ID")"
if [ "$ANALYTICS_CODE" != "200" ]; then
  echo "❌ /api/analytics/customer status=$ANALYTICS_CODE"
  exit 1
fi

echo "✅ Smoke test OK"
