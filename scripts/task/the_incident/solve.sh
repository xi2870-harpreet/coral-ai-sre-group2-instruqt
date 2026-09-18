#!/bin/bash
set -euxo pipefail
# Solve: full-chain defensive - ensure the incident exists, then answer it.

if ! kubectl get deployment payments -o jsonpath='{.spec.template.spec.containers[0].env}' 2>/dev/null | grep -q SVC_VERSION.*v2; then
  kubectl set env deployment/payments SVC_VERSION=v2 PAYMENT_GATEWAY_URL- || true
  kubectl rollout status deployment/payments --timeout=120s || true
fi

for i in 1 2 3 4 5; do
  curl -s -o /dev/null --max-time 8 http://localhost:30080/buy || true
done
/usr/local/bin/shop-log-harvest || true

TRIES=0
until coral sql "SELECT COUNT(*) FROM shopdata.logs WHERE level = 'error' AND service = 'payments'" 2>/dev/null | grep -qE "[1-9]"; do
  TRIES=$((TRIES+1)); [ "$TRIES" -ge 30 ] && { echo "SOLVE FAILED: no payments error logs materialized" >&2; exit 1; }
  curl -s -o /dev/null --max-time 8 http://localhost:30080/buy || true
  /usr/local/bin/shop-log-harvest || true
  sleep 3
done

mkdir -p /root/answers
coral sql "SELECT alert_name, alert_state, severity, summary FROM prometheus.alerts" | tee /root/answers/alerts.txt || echo "alerts query failed at solve time" > /root/answers/alerts.txt
echo "payments" > /root/answers/q1.txt
exit 0
