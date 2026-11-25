#!/usr/bin/env bash
# Start the image over stdio, run initialize + tools/list, and check the tool
# count. No Xero credentials are needed: the token file is only read on the
# first tool call, not at startup.
set -euo pipefail

IMAGE="${1:?usage: smoke-test.sh IMAGE}"
MIN_TOOLS="${MIN_TOOLS:-70}"

requests='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke-test","version":"0"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}'

out=$(printf '%s\n' "$requests" | timeout 30 docker run -i --rm \
  -e XERO_CLIENT_ID=smoke -e XERO_CLIENT_SECRET=smoke \
  "$IMAGE" || true)

server=$(printf '%s\n' "$out" | jq -r 'select(.id==1) | .result.serverInfo.name // empty')
count=$(printf '%s\n' "$out" | jq -r 'select(.id==2) | .result.tools | length')

echo "server: ${server:-<none>}"
echo "tools:  ${count:-0}"

if [ -z "$server" ] || [ "${count:-0}" -lt "$MIN_TOOLS" ]; then
  echo "Smoke test failed. Raw output:" >&2
  printf '%s\n' "$out" >&2
  exit 1
fi
echo "OK"
