# FlatScan hosted web GUI — single container.
#
# FlatScan's --web server binds 127.0.0.1 only and pins Host/Origin to
# localhost (anti-DNS-rebinding + CSRF), and it ships with NO authentication.
# To expose it on a real domain we run Caddy in the SAME container: Caddy
# terminates TLS, enforces Basic Auth, and reverse-proxies to flatscan on
# loopback while rewriting Host/Origin back to localhost so flatscan's guard
# passes. Separate containers would not work — flatscan is unreachable off its
# own loopback by design.

# ---- build flatscan ----
FROM golang:1.25-bookworm AS build
WORKDIR /src
# The Go module lives in the "source go" directory (note the space).
COPY ["source go", "./"]
RUN CGO_ENABLED=0 go build -trimpath -o /flatscan .

# ---- runtime: Caddy + flatscan ----
FROM caddy:2-alpine
COPY --from=build /flatscan /usr/local/bin/flatscan
COPY deploy/Caddyfile /etc/caddy/Caddyfile
COPY deploy/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /usr/local/bin/flatscan
ENV FLATSCAN_PORT=5000
# 80/443 are Caddy's public ports. flatscan's 5000 stays on loopback, unexposed.
EXPOSE 80 443
ENTRYPOINT ["/entrypoint.sh"]
