#!/bin/bash

set -Eeuo pipefail

# Usage:
# sudo bash scripts/deploy.sh v2 2.0 green 5002

IMAGE_TAG="${1:-}"
APP_VERSION="${2:-}"
APP_COLOR="${3:-}"
TARGET_PORT="${4:-}"

UPSTREAM_FILE="/etc/nginx/conf.d/flask-upstream.conf"

if [[ -z "$IMAGE_TAG" || -z "$APP_VERSION" || -z "$APP_COLOR" || -z "$TARGET_PORT" ]]; then
    echo "Usage: sudo bash scripts/deploy.sh IMAGE_TAG APP_VERSION APP_COLOR PORT"
    exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
    echo "Please run this script with sudo."
    exit 1
fi

if [[ ! -f "$UPSTREAM_FILE" ]]; then
    echo "Nginx upstream configuration not found: $UPSTREAM_FILE"
    exit 1
fi

IMAGE="zero-downtime-app:${IMAGE_TAG}"
CONTAINER_NAME="flask-${IMAGE_TAG}"

# Find the port currently receiving traffic.
CURRENT_PORT=$(awk '/server 127.0.0.1:/ {sub(/^.*:/, "", $2); sub(/;$/, "", $2); print $2}' "$UPSTREAM_FILE")

if [[ -z "$CURRENT_PORT" ]]; then
    echo "Could not identify the current Nginx upstream port."
    exit 1
fi

if [[ "$CURRENT_PORT" == "$TARGET_PORT" ]]; then
    echo "ERROR: Port $TARGET_PORT is currently active."
    echo "Choose the inactive application port to avoid interrupting traffic."
    exit 1
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "ERROR: Docker image $IMAGE does not exist."
    exit 1
fi

echo "Current active port: $CURRENT_PORT"
echo "Preparing version $APP_VERSION on port $TARGET_PORT..."

# Replace only the inactive version's container.
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p "127.0.0.1:${TARGET_PORT}:5000" \
    -e "APP_VERSION=${APP_VERSION}" \
    -e "APP_COLOR=${APP_COLOR}" \
    "$IMAGE"

# Validate the JSON version returned by an application endpoint.
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

# Check the new container before switching traffic.
echo "Checking application health..."

HEALTHY=false

for attempt in {1..20}; do
    if response_has_version "http://127.0.0.1:${TARGET_PORT}/health" "$APP_VERSION"; then
        HEALTHY=true
        break
    fi

    echo "Health check attempt ${attempt}/20..."
    sleep 2
done

if [[ "$HEALTHY" != "true" ]]; then
    echo "ERROR: New version failed its health check."
    docker logs "$CONTAINER_NAME" || true
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    echo "Existing application remains active on port $CURRENT_PORT."
    exit 1
fi

echo "New version is healthy."

# Switch Nginx to the new application.
restore_previous_version() {
    echo "Restoring previous Nginx upstream..."

    cat > "$UPSTREAM_FILE" <<EOF
upstream flask_backend {
    server 127.0.0.1:${CURRENT_PORT};
}
EOF

    nginx -t && systemctl reload nginx
}

cat > "$UPSTREAM_FILE" <<EOF
upstream flask_backend {
    server 127.0.0.1:${TARGET_PORT};
}
EOF

if ! nginx -t; then
    echo "ERROR: Nginx configuration test failed."
    restore_previous_version
    exit 1
fi

if ! systemctl reload nginx; then
    echo "ERROR: Nginx reload failed."
    restore_previous_version
    exit 1
fi

# Verify traffic reaches the expected version.
echo "Waiting for Nginx to serve the new version..."

VERIFIED=false

for attempt in {1..10}; do
    if response_has_version "http://127.0.0.1/" "$APP_VERSION"; then
        VERIFIED=true
        break
    fi

    echo "Traffic verification attempt ${attempt}/10..."
    sleep 1
done

if [[ "$VERIFIED" != "true" ]]; then
    echo "ERROR: Traffic verification failed after retries."
    restore_previous_version
    exit 1
fi

echo "----------------------------------------"
echo "DEPLOYMENT SUCCESSFUL"
echo "Application version: $APP_VERSION"
echo "Application color:   $APP_COLOR"
echo "Active port:         $TARGET_PORT"
echo "----------------------------------------"
