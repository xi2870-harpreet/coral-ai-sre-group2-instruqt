#!/bin/bash
set -euxo pipefail
# Solve: full-chain defensive - heal if needed, attempt mutations, write and
# install the spec, verify it answers.

kubectl get deployment payments >/dev/null 2>&1 && {
  kubectl set env deployment/payments SVC_VERSION=v1 PAYMENT_GATEWAY_URL=http://gateway.internal:9099 || true
  kubectl rollout status deployment/payments --timeout=120s || true
}

mkdir -p /root/answers
coral sql "DELETE FROM k8s.pods WHERE name LIKE 'payments%'" 2>&1 | tee /root/answers/mutation-attempt.txt || true
[ -s /root/answers/mutation-attempt.txt ] || echo "mutation refused by coral (no output captured)" > /root/answers/mutation-attempt.txt
coral sql "UPDATE shopdata.tickets SET status = 'closed'" || true

mkdir -p /root/specs
[ -d /root/specs/shopapi.yaml ] && rm -rf /root/specs/shopapi.yaml
cat > /root/specs/shopapi.yaml << 'SPECEOF'
name: shopapi
description: The Reef Shop's own stats API, exposed to agents as SQL
version: 0.1.0
dsl_version: 3
backend: http
base_url: http://localhost:30080
tables:
- name: service_stats
  description: Per-service request success and error counts
  request:
    method: GET
    path: /api/stats
  response:
    rows_path: [stats]
  columns:
  - {name: service, type: Utf8}
  - {name: ok_requests, type: Int64}
  - {name: error_requests, type: Int64}
SPECEOF

coral source lint /root/specs/shopapi.yaml
coral source list | grep -q shopapi || coral source add --file /root/specs/shopapi.yaml

TRIES=0
until coral sql "SELECT service FROM shopapi.service_stats LIMIT 1" 2>/dev/null | grep -qE "orders|payments"; do
  TRIES=$((TRIES+1)); [ "$TRIES" -ge 15 ] && { echo "SOLVE FAILED: shopapi not answering" >&2; exit 1; }
  sleep 2
done
exit 0
