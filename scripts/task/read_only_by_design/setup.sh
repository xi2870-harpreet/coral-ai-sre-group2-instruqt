#!/bin/bash
set -euxo pipefail
# Heal the incident (roll payments back to v1) so the finale runs on a
# healthy stack. Defensive: works whether or not the incident condition ran.

if kubectl get deployment payments >/dev/null 2>&1; then
  kubectl set env deployment/payments SVC_VERSION=v1 PAYMENT_GATEWAY_URL=http://gateway.internal:9099
  kubectl rollout status deployment/payments --timeout=120s || true
fi

# Repair the specs workspace defensively (learner may arrive with damage
# from an earlier attempt): a DIRECTORY named shopapi.yaml gets moved aside,
# a missing shopapi.yaml is re-seeded, and an overwritten shopdata.yaml is
# restored from the canonical backup.
if [ -d /root/specs/shopapi.yaml ]; then
  mv /root/specs/shopapi.yaml "/root/specs/.shopapi.yaml.dir.$(date +%s)" || true
fi
[ -f /root/specs/shopapi.yaml ] || printf '# Challenge 5, Step 3: replace this line with the shopapi spec from the instructions.\n' > /root/specs/shopapi.yaml
if [ -f /opt/shop/shopdata.yaml.bak ] && ! cmp -s /root/specs/shopdata.yaml /opt/shop/shopdata.yaml.bak; then
  cp /opt/shop/shopdata.yaml.bak /root/specs/shopdata.yaml
fi

# A little healthy traffic so post-fix stats look alive.
sleep 3
for i in 1 2 3; do
  curl -s -o /dev/null --max-time 8 http://localhost:30080/buy || true
done
/usr/local/bin/shop-log-harvest || true
echo "Payments healed to v1."
