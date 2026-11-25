# xero-mcp-docker

Docker image for the [aspiers/xero-mcp-server **best-of-breed**](https://github.com/aspiers/xero-mcp-server/tree/best-of-breed) fork of the official Xero MCP server, published to GHCR.

Why this fork: its `XERO_TOKEN_FILE` mode uses a normal OAuth2 authorization-code flow with a rolling refresh token, so you sign in once and it keeps itself alive. It works in every region (no Custom Connection, which isn't sold outside AU/NZ/UK/US anyway) and on Xero's free Starter developer tier. It also bundles ~30 open community PRs: 79 tools vs 51 upstream.

This repo holds no server code. The Dockerfile clones the fork at a pinned tag **and** commit SHA and fails the build if they don't match.

| | |
|---|---|
| Image | `ghcr.io/scumbug/xero-mcp-docker` |
| Upstream pin | `best-of-breed-2026-09-23-2` @ `fdc8a94` |
| HTTP bridge | [supergateway](https://github.com/supercorp-ai/supergateway) 4.3.0 |
| Platforms | `linux/amd64`, `linux/arm64` |

## Modes

| Command | What it does |
|---|---|
| `http` | Long-running Streamable HTTP server. One endpoint per org listed in `XERO_ORGS`, at `/<org>/mcp` on port 8000. Requires an API key. For compose deployments and MCP gateways/portals. |
| `stdio` (default) | One org over stdin/stdout, for clients that launch the server themselves (`docker run -i`). |
| `auth` | One-time OAuth sign-in that writes the token file. |

Every org endpoint is the same server pinned to a different org (`XERO_TENANT_ID`). All of them share one token file; the fork locks it, so concurrent refreshes are safe.

## Setup (Docker Compose, HTTP mode)

### 1. Create one Xero Web app

At <https://developer.xero.com/app/manage> create a **Web app**:

- Redirect URI: `http://localhost:53682/callback`
- Copy the client ID and generate a client secret

One app and one sign-in cover all your orgs. The Starter tier allows 5 connections.

### 2. Make the data folder and env file

```bash
mkdir -p /mnt/user/appdata/xero-mcp
chown 1000:1000 /mnt/user/appdata/xero-mcp   # container runs as uid 1000
chmod 700 /mnt/user/appdata/xero-mcp
```

On Unraid you can instead leave the folder as `nobody:users` and set `user: "99:100"` in the compose file.

`/mnt/user/appdata/xero-mcp/xero.env` (chmod 600):

```env
XERO_CLIENT_ID=your_client_id
XERO_CLIENT_SECRET=your_client_secret
XERO_SCOPES=accounting.invoices accounting.payments accounting.banktransactions accounting.manualjournals accounting.contacts accounting.settings accounting.attachments.read accounting.reports.aged.read accounting.reports.balancesheet.read accounting.reports.profitandloss.read accounting.reports.trialbalance.read
# Clients must send this as "Authorization: Bearer <key>" or "X-API-Key: <key>".
# Generate with: openssl rand -hex 32
SUPERGATEWAY_API_KEY=change-me
```

`offline_access` is added to the scopes automatically. Payroll scopes (`payroll.settings payroll.employees payroll.timesheets`) are left out; add them only if your orgs are in a region Xero Payroll's API supports. Only grant the write scopes you want an agent to have.

### 3. Copy the compose file

Start from [`compose.example.yaml`](compose.example.yaml). Leave `XERO_ORGS` as the placeholders for now; you get the tenant IDs in the next step.

### 4. Sign in once

The OAuth callback listens on `127.0.0.1:53682`, which is why the auth service uses host networking. From the machine with your browser:

```bash
ssh -L 53682:localhost:53682 root@<docker-host>
# then, in the compose project folder on that host:
docker compose run --rm xero-mcp-auth
```

Open the URL it prints, sign in and pick an org. If Xero's consent screen only lets you choose one org at a time, run it again for each one. When it finishes, it prints every connected org's **tenant ID**.

### 5. Fill in `XERO_ORGS` and start it

```yaml
XERO_ORGS: >-
  org-a=<tenant-id>
  org-b=<tenant-id>
```

Names: lowercase letters, digits and dashes. Then:

```bash
docker compose up -d
curl -s http://<docker-host>:8000/healthz   # → ok
```

### 6. Point your MCP client or gateway at it

Each org is its own MCP server:

```
URL:  http://<docker-host>:8000/org-a/mcp
Auth: Authorization: Bearer <SUPERGATEWAY_API_KEY>
```

Registering each org as a separate server, rather than one combined server, means a write can't land in the wrong company because the model picked the wrong org, and you can switch orgs on and off individually.

## stdio mode

For clients that launch servers themselves:

```json
{
  "mcpServers": {
    "xero-org-a": {
      "command": "docker",
      "args": [
        "run", "-i", "--rm",
        "--env-file", "/mnt/user/appdata/xero-mcp/xero.env",
        "-e", "XERO_TENANT_ID=<org-a-tenant-id>",
        "-v", "/mnt/user/appdata/xero-mcp:/data",
        "ghcr.io/scumbug/xero-mcp-docker:best-of-breed-2026-09-23-2"
      ]
    }
  }
}
```

Use `-i` and never `-t`: a TTY corrupts the stdio stream. Always set `XERO_TENANT_ID`; without it, writes go to whichever org Xero lists first.

## Environment variables

| Variable | Mode | |
|---|---|---|
| `XERO_CLIENT_ID`, `XERO_CLIENT_SECRET` | all | From your Xero Web app |
| `XERO_SCOPES` | `auth` | Scopes to request at sign-in |
| `XERO_TOKEN_FILE` | all | Default `/data/tokens.json` |
| `XERO_ORGS` | `http` | `name=tenant-id` pairs, separated by spaces, commas or newlines |
| `SUPERGATEWAY_API_KEY` / `SUPERGATEWAY_API_KEY_FILE` | `http` | Required; `http` mode refuses to start without one |
| `PORT` | `http` | Default `8000` |
| `GATEWAY_LOG_LEVEL` | `http` | Default `none`. `info` and `debug` log every MCP message body, which is your accounting data. |
| `XERO_TENANT_ID` | `stdio` | Org to pin to |

## Tags

- `latest`: newest build from `main`
- `best-of-breed-2026-09-23-2`: the upstream snapshot the image was built from (pin this one)
- `sha-<short>`: exact commit of this repo
- `X.Y.Z`: when this repo gets a `vX.Y.Z` git tag

The image is rebuilt weekly so the Node base image keeps getting security patches. CI smoke-tests both transports (`initialize` + `tools/list`, and a 401 without the API key) before publishing.

## Bumping upstream

Edit `UPSTREAM_REF` and `UPSTREAM_SHA` at the top of the `Dockerfile` (or `SUPERGATEWAY_VERSION`) and push.

```bash
git ls-remote --tags https://github.com/aspiers/xero-mcp-server.git 'best-of-breed*'
```

## Caveats

- The fork is a community snapshot, not a maintained release. Its author has **not live-tested the write tools**.
- Write tools change data with no confirmation step and carry no read-only/destructive hints. Point new workflows at the Xero Demo Company first.
- `http` mode is plain HTTP. Keep port 8000 on a trusted network and put TLS in front (a tunnel or reverse proxy) for anything beyond it.
- `tokens.json` holds a refresh token with write access to every connected org. Keep the folder private and back it up like a secret.
- Refresh tokens expire if unused for a long period (about 60 days). Any org endpoint that gets used refreshes the shared file and keeps all of them alive. If it does expire, rerun step 4.

## Credits

Server code: [XeroAPI/xero-mcp-server](https://github.com/XeroAPI/xero-mcp-server) (MIT) and the community PRs combined by [@aspiers](https://github.com/aspiers) in [XeroAPI/xero-mcp-server#315](https://github.com/XeroAPI/xero-mcp-server/issues/315). HTTP bridge: [supercorp-ai/supergateway](https://github.com/supercorp-ai/supergateway) (MIT). This repo's packaging is MIT.
