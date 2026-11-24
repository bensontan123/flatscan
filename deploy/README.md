# Hosting the FlatScan web GUI

FlatScan already ships a complete single-page web GUI (`--web`). It just can't
run on serverless platforms (Vercel/Netlify): it's a long-running local server,
not an HTTP function, so those deploys 500 with `FUNCTION_INVOCATION_FAILED`.
Host it on a container/VM instead. This folder does that safely.

## How it fits together

```
browser ──HTTPS──► Caddy (TLS + Basic Auth)  ──loopback──► flatscan --web (127.0.0.1:5000)
         your.domain        same container, rewrites Host/Origin → localhost
```

FlatScan's web server is deliberately **loopback-only and unauthenticated** — it
pins `Host`/`Origin` to `localhost` to defeat DNS-rebinding and CSRF, because it
assumes a single analyst on their own machine. To expose it to a browser over
the network we put **Caddy in the same container**, which:

1. Terminates **HTTPS** (auto Let's Encrypt cert for your domain).
2. Enforces **Basic Auth** — the only thing standing between the internet and an
   unauthenticated malware analyzer. **Do not remove it.**
3. Reverse-proxies to `127.0.0.1:5000`, rewriting `Host` and `Origin` back to
   `localhost:5000` so FlatScan's guard accepts the forwarded request.

Separate containers won't work — FlatScan binds its own loopback only, so the
proxy has to share its network namespace (same container).

## Deploy (Docker / any VM with Docker)

Prereqs: a VM with a public IP, Docker + Docker Compose, and a domain whose
DNS A/AAAA record points at the VM. Ports 80 and 443 must be open.

```bash
# 1. Clone and enter the repo
git clone https://github.com/bensontan123/flatscan.git && cd flatscan

# 2. Generate a Basic Auth password hash
docker run --rm caddy:2-alpine caddy hash-password --plaintext 'a-strong-password'
#    → copy the $2a$... bcrypt hash it prints

# 3. Create deploy/.env
cat > deploy/.env <<'ENV'
FLATSCAN_SITE=scan.example.com
FLATSCAN_USER=analyst
FLATSCAN_PASSWORD_HASH=$2a$14$REPLACE_WITH_THE_HASH_FROM_STEP_2
ENV

# 4. Build and start
docker compose --env-file deploy/.env -f deploy/docker-compose.yml up -d --build

# 5. Open https://scan.example.com  (browser will prompt for the user/password)
```

`FLATSCAN_SITE` is the Caddy listen address: a hostname (e.g.
`scan.example.com`) serves auto-HTTPS on :443; `:80` serves plain HTTP for a
platform that terminates TLS itself. `FLATSCAN_PORT` defaults to 5000.

## Deploy on Fly.io

**Free `*.fly.dev` hostname (no custom domain)** — use `deploy/fly.dev.toml`.
Fly's edge terminates TLS, so Caddy serves HTTP on :80 (`FLATSCAN_SITE=:80`,
already set in that config):

```bash
# fly CLI installed and logged in (fly auth login)
fly launch --no-deploy --copy-config --config deploy/fly.dev.toml --dockerfile deploy/Dockerfile
fly secrets set FLATSCAN_USER=analyst \
  FLATSCAN_PASSWORD_HASH="$(docker run --rm caddy:2-alpine caddy hash-password --plaintext 'a-strong-password')"
fly deploy --config deploy/fly.dev.toml
# → https://<app>.fly.dev
```

**Custom domain** — use `deploy/fly.toml` instead (Fly passes TCP through, Caddy
gets the cert). Set `FLATSCAN_SITE=your.domain` plus the user/hash as secrets,
allocate IPs, point DNS, then `fly deploy`. See the comments in that file.

On Railway / Render, point the platform at `deploy/Dockerfile` (build context =
repo root), set `FLATSCAN_USER`, `FLATSCAN_PASSWORD_HASH`, and `FLATSCAN_SITE=:80`,
and let the platform's own TLS terminate and proxy to container port 80.

## Security notes — read before exposing this

- This is a **malware-analysis tool that accepts arbitrary file uploads** and
  runs analysis on them. Anyone who gets past the proxy can submit samples and
  read recovered IOCs/C2 config. Treat the endpoint as sensitive.
- **Keep Basic Auth on**, use a strong unique password, and prefer also
  restricting by source IP (Caddy `@allowed` matcher, a firewall, or a VPN/WireGuard
  front) so it isn't open to the whole internet.
- Uploaded samples live in per-job temp dirs and are reaped automatically
  (30 min finished / 4 h hard cap), but while present they are real malware on
  your host. Run on an isolated VM you're willing to treat as contaminated.
- Only analyze samples you're authorized to handle.

## Why not Vercel

FlatScan is a persistent server (and in CLI form a one-shot command), not a
serverless function. Vercel builds the Go binary then runs it expecting a
long-running HTTP server; with no target argument it prints its usage error and
exits, so every request returns `FUNCTION_INVOCATION_FAILED`. There is no way to
pass `--web` to a Vercel Go executable, and even `--web` is a long-running
loopback server. Host it as above instead.
