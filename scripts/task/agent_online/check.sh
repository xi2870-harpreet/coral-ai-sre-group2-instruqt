#!/bin/bash
# Check: MCP registration + agent round-trip evidence.

# 1. Coral registered with Claude Code
MCP_LIST=$(claude mcp list 2>/dev/null)
if ! echo "$MCP_LIST" | grep -qi "coral"; then
  echo "Claude Code doesn't know about Coral yet. Run Step 1: claude mcp add --scope user coral -- coral mcp-stdio"
  exit 1
fi

# 2. Warmup marker exists and contains a count
if [ ! -s /root/answers/agent-warmup.txt ]; then
  echo "Run the Step 3 marker command so we know the round-trip worked - it writes /root/answers/agent-warmup.txt."
  exit 1
fi

exit 0
