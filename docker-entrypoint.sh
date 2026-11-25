#!/bin/sh
# Modes:
#   stdio  (default) MCP over stdin/stdout, one org (set XERO_TENANT_ID)
#   http             Streamable HTTP via supergateway, one endpoint per org in
#                    XERO_ORGS at /<name>/mcp; requires an API key
#   auth             one-time OAuth bootstrap that writes XERO_TOKEN_FILE
#   *                anything else is run as-is (e.g. sh for debugging)
set -eu

APP_DIR="${APP_DIR:-/app}"
SERVER="${APP_DIR}/dist/index.js"

mode="${1:-stdio}"
[ "$#" -gt 0 ] && shift

case "$mode" in
  stdio)
    exec node "$SERVER" "$@"
    ;;

  auth)
    exec node "$SERVER" auth "$@"
    ;;

  http)
    if [ -z "${XERO_ORGS:-}" ]; then
      echo "http mode needs XERO_ORGS, e.g. XERO_ORGS=\"org-a=<tenant-id> org-b=<tenant-id>\"" >&2
      exit 1
    fi
    # Every endpoint can write to your books: refuse to start without a key.
    if [ -z "${SUPERGATEWAY_API_KEY:-}" ] && [ -z "${SUPERGATEWAY_API_KEY_FILE:-}" ]; then
      echo "http mode needs SUPERGATEWAY_API_KEY or SUPERGATEWAY_API_KEY_FILE" >&2
      exit 1
    fi
    config="${GATEWAY_CONFIG:-/tmp/gateway.json}"
    node "${APP_DIR}/gateway-config.mjs" "$SERVER" > "$config"
    exec supergateway --config "$config" "$@"
    ;;

  *)
    exec "$mode" "$@"
    ;;
esac
