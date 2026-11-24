#!/bin/sh
# Start flatscan on loopback, then Caddy in the foreground as PID-visible server.
set -eu

PORT="${FLATSCAN_PORT:-5000}"

# flatscan binds 127.0.0.1:$PORT (its own choice); Caddy reaches it on the
# shared loopback because they run in the same container/network namespace.
flatscan --web --web-port "$PORT" &
flatscan_pid=$!

# Forward termination so `docker stop` shuts flatscan down cleanly too.
trap 'kill -TERM "$flatscan_pid" 2>/dev/null || true' INT TERM

# Wait until flatscan is accepting connections before fronting it with Caddy.
i=0
while [ "$i" -lt 30 ]; do
    if wget -q -O /dev/null --header="Host: localhost:$PORT" "http://127.0.0.1:$PORT/" 2>/dev/null; then
        break
    fi
    i=$((i + 1))
    sleep 1
done

# Caddy in the foreground; it reads the domain, user and password hash from env.
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
