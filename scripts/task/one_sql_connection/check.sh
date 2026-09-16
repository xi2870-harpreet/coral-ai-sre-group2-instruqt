#!/bin/bash
# Check: sources connected + learner ran catalog and JOIN queries.

# 1. All three sources present
SRC_LIST=$(coral source list 2>/dev/null)
if [ -z "$SRC_LIST" ]; then
  echo "Coral isn't answering. Run 'coral source list' in the Terminal to see what's wrong."
  exit 1
fi
for SRC in k8s prometheus shopdata; do
  if ! echo "$SRC_LIST" | grep -q "$SRC"; then
    echo "The '$SRC' source is missing from 'coral source list'. It was connected during setup - ask for help if it vanished."
    exit 1
  fi
done

# 2. Cross-source JOIN actually works right now (live-truth)
JOIN_OUT=$(coral sql "SELECT p.name FROM k8s.pods p LEFT JOIN shopdata.logs l ON l.pod = p.name WHERE p.namespace = 'default' LIMIT 1" 2>&1)
if [ $? -ne 0 ] || [ -z "$JOIN_OUT" ]; then
  echo "A cross-source JOIN between k8s.pods and shopdata.logs isn't returning rows. Re-run the Step 4 query and read its error output."
  exit 1
fi

# 3. Learner ran the Step 4 JOIN and saved the evidence
if [ ! -s /root/answers/first-join.txt ]; then
  echo "Run the Step 4 cross-source JOIN - it saves its output to /root/answers/first-join.txt, which is what this check grades."
  exit 1
fi
if ! grep -qE "frontend|orders|payments" /root/answers/first-join.txt 2>/dev/null; then
  echo "/root/answers/first-join.txt doesn't contain pod rows - re-run the Step 4 JOIN and check its output for errors."
  exit 1
fi

exit 0
