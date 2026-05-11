#!/bin/sh
set -e

if [ -z "${BASIC_AUTH_USER:-}" ]; then
    echo "ERROR: BASIC_AUTH_USER is required" >&2
    exit 1
fi

if [ -z "${BASIC_AUTH_PASSWORD:-}" ]; then
    echo "ERROR: BASIC_AUTH_PASSWORD is required" >&2
    exit 1
fi

if [ -z "${API_KEY:-}" ]; then
    echo "ERROR: API_KEY is required" >&2
    exit 1
fi

htpasswd -cb /etc/nginx/.htpasswd "$BASIC_AUTH_USER" "$BASIC_AUTH_PASSWORD"

envsubst '${API_KEY}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

nginx -t || { echo "ERROR: nginx config invalid" >&2; exit 1; }

exec nginx -g "daemon off;"
