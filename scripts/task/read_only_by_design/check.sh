#!/bin/bash
# Check: mutation attempted + custom source installed and queryable.

# 1. Learner attempted a mutation through Coral and kept the receipt
if [ ! -s /root/answers/mutation-attempt.txt ]; then
  echo "Run the Step 1 DELETE attempt - it saves Coral's refusal to /root/answers/mutation-attempt.txt. Seeing it refused IS the lesson."
  exit 1
fi

# 2. shopapi spec file contains a real spec (not the placeholder comment)
if ! grep -q "backend: http" /root/specs/shopapi.yaml 2>/dev/null; then
  echo "Open shopapi.yaml in the Spec Editor (Step 3) and replace the placeholder comment with the spec from the instructions."
  exit 1
fi

# 3. shopapi source installed
if ! coral source list 2>/dev/null | grep -q "shopapi"; then
  echo "The shopapi source isn't installed yet. Run: coral source lint /root/specs/shopapi.yaml && coral source add --file /root/specs/shopapi.yaml"
  exit 1
fi

# 4. It answers queries (live-truth)
STATS_OUT=$(coral sql "SELECT service FROM shopapi.service_stats LIMIT 1" 2>&1)
if [ $? -ne 0 ] || ! echo "$STATS_OUT" | grep -qE "orders|payments"; then
  echo "shopapi.service_stats isn't returning rows. Re-run the Step 4 query and read the error - did the spec paste exactly?"
  exit 1
fi

exit 0
