#!/usr/bin/env bash
# Smoke-tests both transports without Xero credentials: the token file is only
# read on the first tool call, not at startup or for initialize/tools/list.
#   1. stdio: initialize + tools/list over stdin/stdout
#   2. http:  /healthz, 401 without key, initialize + tools/list per org path
set -euo pipefail

IMAGE="${1:?usage: smoke-test.sh IMAGE}"
MIN_TOOLS="${MIN_TOOLS:-70}"
PORT="${SMOKE_PORT:-18000}"
KEY="smoke-test-key"
ORGS="org-a=11111111-1111-1111-1111-111111111111 org-b=22222222-2222-2222-2222-222222222222"

INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke-test","version":"0"}}}'
INITIALIZED='{"jsonrpc":"2.0","method":"notifications/initialized"}'
LIST='{"jsonrpc":"2.0","id":2,"method":"tools/list"}'

fail() { echo "FAIL: $*" >&2; exit 1; }

check_tools() { # $1 label, $2 count
  echo "$1: ${2:-0} tools"
  [ "${2:-0}" -ge "$MIN_TOOLS" ] || fail "$1 listed fewer than $MIN_TOOLS tools"
}

# --- 1. stdio --------------------------------------------------------------
out=$(printf '%s\n' "$INIT" "$INITIALIZED" "$LIST" | timeout 30 docker run -i --rm \
  -e XERO_CLIENT_ID=smoke -e XERO_CLIENT_SECRET=smoke "$IMAGE" || true)
server=$(printf '%s\n' "$out" | jq -r 'select(.id==1) | .result.serverInfo.name // empty')
[ -n "$server" ] || { printf '%s\n' "$out" >&2; fail "stdio initialize got no serverInfo"; }
echo "stdio server: $server"
check_tools "stdio" "$(printf '%s\n' "$out" | jq -r 'select(.id==2) | .result.tools | length')"

# --- 2. http ---------------------------------------------------------------
cid=$(docker run -d --rm -p "127.0.0.1:${PORT}:8000" \
  -e XERO_CLIENT_ID=smoke -e XERO_CLIENT_SECRET=smoke \
  -e XERO_ORGS="$ORGS" -e SUPERGATEWAY_API_KEY="$KEY" \
  "$IMAGE" http)
trap 'docker logs "$cid" >&2 2>&1 | tail -40 || true; docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT

base="http://127.0.0.1:${PORT}"
for _ in $(seq 1 30); do
  curl -fs "$base/healthz" >/dev/null 2>&1 && break
  sleep 1
done
[ "$(curl -s "$base/healthz")" = "ok" ] || fail "http /healthz not ok"
echo "http /healthz: ok"

post() { # $1 path, $2 body, rest: extra curl args
  local path="$1" body="$2"; shift 2
  curl -s -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -H 'MCP-Protocol-Version: 2025-06-18' "$@" -d "$body" "$base$path"
}
# Responses may be plain JSON or a single SSE event.
json() { sed -n 's/^data: //; /^{/p'; }

code=$(post /org-a/mcp "$INIT" -o /dev/null -w '%{http_code}')
[ "$code" = "401" ] || fail "request without key returned $code, expected 401"
echo "http no key: 401"

for org in org-a org-b; do
  name=$(post "/$org/mcp" "$INIT" -H "Authorization: Bearer $KEY" | json | jq -r '.result.serverInfo.name // empty')
  [ -n "$name" ] || fail "http /$org/mcp initialize got no serverInfo"
  check_tools "http /$org/mcp" "$(post "/$org/mcp" "$LIST" -H "X-API-Key: $KEY" | json | jq -r '.result.tools | length')"
done

trap 'docker rm -f "$cid" >/dev/null 2>&1 || true' EXIT
echo "OK"
