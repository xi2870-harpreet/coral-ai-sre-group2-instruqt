#!/bin/bash
set -euxo pipefail
# Solve: full-chain defensive - register MCP, leave history + marker.

command -v claude >/dev/null 2>&1 || { echo "SOLVE FAILED: claude CLI missing" >&2; exit 1; }

claude mcp list 2>/dev/null | grep -qi coral || claude mcp add --scope user coral -- coral mcp-stdio

mkdir -p /root/answers
coral sql "SELECT COUNT(*) AS error_lines FROM shopdata.logs WHERE level = 'error'" | tee /root/answers/agent-warmup.txt
exit 0
