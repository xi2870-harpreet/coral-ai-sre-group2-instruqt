#!/bin/bash
set -euxo pipefail
# Fire the incident - roll out the "v2 bad deploy" of payments. v2 ships
# without PAYMENT_GATEWAY_URL, so /charge returns 500s, checkout breaks, and
# PaymentsHighErrorRate fires within ~2 minutes.

# Defensive: ensure payments exists (learner may have skipped here).
TRIES=0
until kubectl get deployment payments >/dev/null 2>&1; do
  TRIES=$((TRIES+1)); [ "$TRIES" -ge 30 ] && { echo "SETUP FAILED: payments deployment missing" >&2; exit 1; }
  sleep 2
done

# The bad deploy: bump version label, DROP the gateway env var.
kubectl set env deployment/payments SVC_VERSION=v2 PAYMENT_GATEWAY_URL-
kubectl rollout status deployment/payments --timeout=120s || { echo "SETUP FAILED: v2 rollout" >&2; exit 1; }

# Drive traffic so errors, metrics, and logs accumulate immediately.
sleep 3
for i in 1 2 3 4 5 6 7 8; do
  curl -s -o /dev/null --max-time 8 http://localhost:30080/buy || true
  sleep 1
done
/usr/local/bin/shop-log-harvest || true

echo "Incident is live: payments v2 rolled out without PAYMENT_GATEWAY_URL."
