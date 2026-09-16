#!/bin/bash
# Check: live-truth grading - the submitted answer must name the service that
# is actually failing right now, and the learner must have investigated.

# 1. Answer submitted
if [ ! -s /root/answers/q1.txt ]; then
  echo "No answer recorded yet. When you know which service is the root cause, run: submit \"<root-cause-service>\""
  exit 1
fi

# 2. Compute live truth: the service whose deployment carries the v2 bad
# deploy. (NOT "top error producer" - the cascade yields a ~1:1:1 error
# ratio across payments/orders/frontend, which made that heuristic a
# nondeterministic tie. The bad deploy marker is the actual ground truth.)
TRUTH=""
for SVC in frontend orders payments; do
  V=$(kubectl get deployment "$SVC" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="SVC_VERSION")].value}' 2>/dev/null)
  if [ "$V" = "v2" ]; then TRUTH="$SVC"; break; fi
done
if [ -z "$TRUTH" ]; then
  # Fallback: the service whose errors are self-originated (its message
  # doesn't blame a downstream service) - matches payments' log line.
  TRUTH=$(grep '"level": "error"' /root/data/logs.jsonl 2>/dev/null | grep -v "returned an error" | grep -oE '"service": "(frontend|orders|payments)"' | head -1 | grep -oE "frontend|orders|payments")
fi
if [ -z "$TRUTH" ]; then
  echo "The grader can't compute the live answer - is Coral responding? Run the Step 2 alerts query and try again."
  exit 1
fi

# 3. Compare (accept minor variants like 'payments service')
ANSWER=$(cat /root/answers/q1.txt)
if ! echo "$ANSWER" | grep -qi "$TRUTH"; then
  echo "Close - but that service is a victim of the cascade, not the cause. Every root failure echoes one error into each service upstream. Re-read the error messages: the root cause names its OWN broken config; the others blame a downstream service."
  exit 1
fi

# 4. Investigation evidence: the Step 2 alerts query was run and saved
if [ ! -s /root/answers/alerts.txt ]; then
  echo "Show your work: run the Step 2 alerts query - it saves its output to /root/answers/alerts.txt, where an SRE's timeline starts."
  exit 1
fi

exit 0
