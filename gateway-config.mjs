// Builds a supergateway --config file from XERO_ORGS.
//
//   XERO_ORGS="org-a=<tenant-id> org-b=<tenant-id>"   (spaces, commas or newlines)
//
// Each org becomes its own MCP server at /<name>/mcp, pinned to its tenant.
// The child processes inherit the container environment (client ID/secret,
// token file, scopes), so only XERO_TENANT_ID differs between them.

const server = process.argv[2];
const raw = process.env.XERO_ORGS ?? "";
const port = Number(process.env.PORT ?? 8000);

const NAME = /^[a-z0-9][a-z0-9-]{0,62}$/;
const TENANT = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const fail = (msg) => {
  process.stderr.write(`XERO_ORGS: ${msg}\n`);
  process.exit(1);
};

const mcpServers = {};
for (const entry of raw.split(/[\s,]+/).filter(Boolean)) {
  const [name, tenant, extra] = entry.split("=");
  if (extra !== undefined || !name || !tenant) fail(`"${entry}" is not name=tenant-id`);
  if (!NAME.test(name)) fail(`"${name}" must be lowercase letters, digits and dashes`);
  if (!TENANT.test(tenant)) fail(`"${tenant}" for ${name} is not a Xero tenant ID (UUID)`);
  if (mcpServers[name]) fail(`"${name}" is listed twice`);
  mcpServers[name] = {
    command: "node",
    args: [server],
    env: { XERO_TENANT_ID: tenant },
  };
}
if (Object.keys(mcpServers).length === 0) fail("no orgs listed");

const config = {
  port,
  host: "0.0.0.0",
  // "info" and "debug" log every MCP message body, i.e. your Xero data.
  logLevel: process.env.GATEWAY_LOG_LEVEL ?? "none",
  healthEndpoint: "/healthz",
  outputTransport: "streamableHttp",
  // Stateless: each request starts the server, which reads the shared token
  // file. Version used when the client's request doesn't name one.
  protocolVersion: "2025-06-18",
  mcpServers,
};

process.stdout.write(JSON.stringify(config, null, 2) + "\n");
process.stderr.write(
  `Serving ${Object.keys(mcpServers).map((n) => `/${n}/mcp`).join(", ")} on :${port}\n`,
);
