# xero-mcp-docker

Docker image for the [aspiers/xero-mcp-server **best-of-breed**](https://github.com/aspiers/xero-mcp-server/tree/best-of-breed) fork of the official Xero MCP server, published to GHCR.

Why this fork: its `XERO_TOKEN_FILE` mode uses a normal OAuth2 authorization-code flow with a rolling refresh token, so you sign in once and it keeps itself alive. It works in every region (no Custom Connection, which isn't sold outside AU/NZ/UK/US anyway) and on Xero's free Starter developer tier. It also bundles ~30 open community PRs: 79 tools vs 51 upstream.

This repo holds no server code. The Dockerfile clones the fork at a pinned tag **and** commit SHA and fails the build if they don't match.

| | |
|---|---|
| Image | `ghcr.io/scumbug/xero-mcp-docker` |
| Upstream pin | `best-of-breed-2026-09-23-2` @ `fdc8a94` |
| Platforms | `linux/amd64`, `linux/arm64` |
| Transport | stdio (`docker run -i`) |

## Tags

- `latest`: newest build from `main`
- `best-of-breed-2026-09-23-2`: the upstream snapshot the image was built from
- `sha-<short>`: exact commit of this repo
- `X.Y.Z`: when this repo gets a `vX.Y.Z` git tag

The image is rebuilt weekly so the Node base image keeps getting security patches.

## Setup

### 1. Create one Xero Web app (covers all your orgs)

At <https://developer.xero.com/app/manage> create a **Web app**:

- Redirect URI: `http://localhost:53682/callback`
- Copy the client ID and generate a client secret

One app and one sign-in can connect several orgs. Starter tier allows 5 connections.

### 2. Make the data folder and env file

```bash
mkdir -p /mnt/user/appdata/xero-mcp
chown 1000:1000 /mnt/user/appdata/xero-mcp   # container runs as uid 1000
chmod 700 /mnt/user/appdata/xero-mcp
```

On Unraid you can instead leave the folder as `nobody:users` and add `--user 99:100` to every `docker run` below.

`/mnt/user/appdata/xero-mcp/xero.env` (chmod 600):

```env
XERO_CLIENT_ID=your_client_id
XERO_CLIENT_SECRET=your_client_secret
XERO_SCOPES=accounting.invoices accounting.payments accounting.banktransactions accounting.manualjournals accounting.contacts accounting.settings accounting.attachments.read accounting.reports.aged.read accounting.reports.balancesheet.read accounting.reports.profitandloss.read accounting.reports.trialbalance.read
```

`offline_access` is added automatically. Payroll scopes (`payroll.settings payroll.employees payroll.timesheets`) are left out; add them only if your orgs are in a region Xero Payroll's API supports. Only list the write scopes you want the agent to have.

### 3. Sign in once

The auth callback listens on `127.0.0.1` inside the container, so use host networking and tunnel the port from the machine with the browser:

```bash
# on your desktop
ssh -L 53682:localhost:53682 root@<unraid-host>

# in that SSH session, on the server
docker run --rm -it --network host \
  --env-file /mnt/user/appdata/xero-mcp/xero.env \
  -v /mnt/user/appdata/xero-mcp:/data \
  ghcr.io/scumbug/xero-mcp-docker auth
```

Open the URL it prints, sign in and pick an org. If Xero's consent screen only lets you choose one org at a time, run `auth` again for each one. When it finishes, it prints every connected org's **tenant ID**. Note them down.

### 4. Add one portal entry per org

Each server process is pinned to one org with `XERO_TENANT_ID`. Without it, writes go to whichever org Xero lists first. All entries share the same token file; the fork locks it, so concurrent refreshes from several containers are safe.

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
    },
    "xero-org-b": { "...": "same, different XERO_TENANT_ID" }
  }
}
```

Use `-i` and never `-t`: a TTY corrupts the stdio stream. If your portal runs inside a container itself, it needs the Docker socket to start these.

## Bumping upstream

Edit `UPSTREAM_REF` and `UPSTREAM_SHA` at the top of the `Dockerfile` and push. CI builds, smoke-tests (`initialize` + `tools/list`), then publishes.

```bash
git ls-remote --tags https://github.com/aspiers/xero-mcp-server.git 'best-of-breed*'
```

## Caveats

- The fork is a community snapshot, not a maintained release. Its author has **not live-tested the write tools**.
- Write tools change data with no confirmation step and carry no read-only/destructive hints. Point new workflows at the Xero Demo Company first.
- `tokens.json` holds a refresh token with write access to every connected org. Keep the folder private and back it up like a secret.
- Refresh tokens expire if unused for a long period (about 60 days). Any of the org entries using the shared file keeps all of them alive. If it does expire, rerun step 3.

## Credits

Server code: [XeroAPI/xero-mcp-server](https://github.com/XeroAPI/xero-mcp-server) (MIT) and the community PRs combined by [@aspiers](https://github.com/aspiers) in [XeroAPI/xero-mcp-server#315](https://github.com/XeroAPI/xero-mcp-server/issues/315). This repo's packaging is MIT.
