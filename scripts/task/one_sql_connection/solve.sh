#!/bin/bash
set -euxo pipefail
# Solve: defensive full-chain - verify sources, then leave history evidence.

TRIES=0
until coral source list 2>/dev/null | grep -q shopdata; do
  TRIES=$((TRIES+1)); [ "$TRIES" -ge 30 ] && { echo "SOLVE FAILED: shopdata source missing" >&2; exit 1; }
  sleep 2
done

coral sql "SELECT schema_name, table_name FROM coral.tables" >/dev/null
mkdir -p /root/answers
coral sql "SELECT p.name AS pod, p.status, COUNT(l.request_id) AS log_lines FROM k8s.pods p LEFT JOIN shopdata.logs l ON l.pod = p.name WHERE p.namespace = 'default' GROUP BY p.name, p.status ORDER BY log_lines DESC" | tee /root/answers/first-join.txt
exit 0
