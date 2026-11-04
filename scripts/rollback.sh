#!/bin/bash

set -Eeuo pipefail

TARGET_PORT="${1:-}"
EXPECTED_VERSION="${2:-}"

UPSTREAM_FILE="/etc/nginx/conf.d/flask-upstream.conf"

if [[ -z "$TARGET_PORT" || -z "$EXPECTED_VERSION" ]]; then
    echo "Usage: sudo bash scripts/rollback.sh PORT EXPECTED_VERSION"
    exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
    echo "Please run this script with sudo."
    exit 1
fi

if [[ ! -f "$UPSTREAM_FILE" ]]; then
    echo "Nginx upstream configuration not found."
    exit 1
fi

response_has_version() {
    local url="$1"
    local expected="$2"
    local response

    response=$(curl -fsS "$url") || return 1

    APP_RESPONSE="$response" EXPECTED_VERSION="$expected" python3 -c '
import json
import os
import sys

try:
    data = json.loads(os.environ["APP_RESPONSE"])
    sys.exit(0 if data.get("version") == os.environ["EXPECTED_VERSION"] else 1)
except (ValueError, KeyError):
    sys.exit(1)
'
}

CURRENT_PORT=$(awk '/server 127.0.0.1:/ {sub(/^.*:/, "", $2); sub(/;$/, "", $2); print $2}' "$UPSTREAM_FILE")

echo "Current active port: $CURRENT_PORT"
echo "Checking rollback target on port $TARGET_PORT..."

if ! response_has_version "http://127.0.0.1:${TARGET_PORT}/health" "$EXPECTED_VERSION"; then
    echo "ERROR: Rollback target is not healthy or has the wrong version."
    exit 1
fi

BACKUP_FILE=$(mktemp)
cp "$UPSTREAM_FILE" "$BACKUP_FILE"

restore_previous_config() {
    echo "Restoring previous Nginx configuration..."
    cp "$BACKUP_FILE" "$UPSTREAM_FILE"

    if nginx -t; then
        systemctl reload nginx
    else
        echo "CRITICAL: Previous configuration could not be validated."
        return 1
    fi
}

cat > "$UPSTREAM_FILE" <<EOF2
upstream flask_backend {
    server 127.0.0.1:${TARGET_PORT};
}
EOF2

if ! nginx -t; then
    echo "ERROR: Nginx configuration test failed."
    restore_previous_config
    rm -f "$BACKUP_FILE"
    exit 1
fi

if ! systemctl reload nginx; then
    echo "ERROR: Nginx reload failed."
    restore_previous_config
    rm -f "$BACKUP_FILE"
    exit 1
fi

echo "Waiting for Nginx to serve the rollback version..."

VERIFIED=false

for attempt in {1..10}; do
    if response_has_version "http://127.0.0.1/" "$EXPECTED_VERSION"; then
        VERIFIED=true
        break
    fi

    echo "Traffic verification attempt ${attempt}/10..."
    sleep 1
done

if [[ "$VERIFIED" != "true" ]]; then
    echo "ERROR: Traffic verification failed after retries."
    restore_previous_config
    rm -f "$BACKUP_FILE"
    exit 1
fi

rm -f "$BACKUP_FILE"

echo "----------------------------------------"
echo "ROLLBACK SUCCESSFUL"
echo "Active application version: $EXPECTED_VERSION"
echo "Active port:                $TARGET_PORT"
echo "----------------------------------------"
