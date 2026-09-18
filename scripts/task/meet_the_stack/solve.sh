#!/bin/bash
set -euxo pipefail
# Solve: produce exactly the state check.sh validates. Idempotent.

TRIES=0
until kubectl get pods -l app=payments -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running; do
  TRIES=$((TRIES+1)); [ "$TRIES" -ge 60 ] && { echo "SOLVE FAILED: payments pod never Running" >&2; exit 1; }
  sleep 2
done

TRIES=0
until [ -s /root/data/logs.jsonl ]; do
  TRIES=$((TRIES+1)); [ "$TRIES" -ge 20 ] && { echo "SOLVE FAILED: logs.jsonl never populated" >&2; exit 1; }
  /usr/local/bin/shop-traffic || true
  /usr/local/bin/shop-log-harvest || true
  sleep 3
done
exit 0
