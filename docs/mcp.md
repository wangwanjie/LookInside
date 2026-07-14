# Use LookInside with MCP clients

LookInside 2.3.11 and later include a local [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) shim. It lets MCP-compatible AI clients inspect the iOS or macOS app that is open in LookInside.

The shim is bundled inside the signed LookInside app. It speaks local `stdio` to the client and forwards requests to the running LookInside host over its local Unix socket; there is no API key or network endpoint to configure.

## Before you configure a client

Make sure all of the following are true:

1. Install an official LookInside 2.3.11 or later release as `/Applications/LookInside.app`.
2. Add the [LookInside server package](https://github.com/LookInsideApp/LookInside-Release) to the Debug build of the app you want to inspect.
3. Run the target app.
4. Open LookInside and connect to the running app from the launch window.
5. Keep LookInside running while the MCP client uses its tools.

Verify that the bundled shim and Node.js are present:

```sh
test -x /Applications/LookInside.app/Contents/Resources/MCP/lookinside-mcp-shim.mjs \
  && command -v node \
  && echo "LookInside MCP shim is installed"
```

If LookInside is installed somewhere else, replace the absolute path in the examples below. Use the shim inside the same LookInside app that you run so the host and shim stay on matching versions.

## Configure an MCP client

LookInside uses the local `stdio` MCP transport. Configure the client to run:

```text
node /Applications/LookInside.app/Contents/Resources/MCP/lookinside-mcp-shim.mjs --socket /Users/<username>/Library/Application Support/LookInside/Host/run/lookinside-host-mcp.sock
```

Replace `/Users/<username>` with your macOS home directory. Start LookInside before using the MCP tools; it creates `lookinside-host-mcp.sock` at runtime. The shim supports the default socket location when `--socket` is omitted, but an explicit path is most portable across MCP clients.

### Codex

Add the server with the Codex CLI:

```sh
codex mcp add lookinside -- node /Applications/LookInside.app/Contents/Resources/MCP/lookinside-mcp-shim.mjs --socket "/Users/<username>/Library/Application Support/LookInside/Host/run/lookinside-host-mcp.sock"
codex mcp get lookinside
```

Start a new Codex session after adding the server. In the Codex terminal UI, `/mcp` shows the active servers. The Codex app, CLI, and IDE extension share MCP configuration for the same Codex host.

The equivalent `~/.codex/config.toml` entry is:

```toml
[mcp_servers.lookinside]
command = "/usr/bin/env"
args = ["node", "/Applications/LookInside.app/Contents/Resources/MCP/lookinside-mcp-shim.mjs", "--socket", "/Users/<username>/Library/Application Support/LookInside/Host/run/lookinside-host-mcp.sock"]
```

See the [official Codex MCP documentation](https://learn.chatgpt.com/docs/extend/mcp?surface=cli) for more client-side options.

### Claude Code

Add LookInside as a user-scoped local server:

```sh
claude mcp add --transport stdio --scope user lookinside \
  -- node /Applications/LookInside.app/Contents/Resources/MCP/lookinside-mcp-shim.mjs --socket "/Users/<username>/Library/Application Support/LookInside/Host/run/lookinside-host-mcp.sock"
claude mcp get lookinside
```

Use `/mcp` inside Claude Code to inspect or reconnect the server. See the [Claude Code MCP documentation](https://code.claude.com/docs/en/mcp) for scope and approval options.

### Claude Desktop

Open **Settings > Developer > Edit Config**, then add this entry to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "lookinside": {
      "command": "node",
      "args": [
        "/Applications/LookInside.app/Contents/Resources/MCP/lookinside-mcp-shim.mjs",
        "--socket",
        "/Users/<username>/Library/Application Support/LookInside/Host/run/lookinside-host-mcp.sock"
      ]
    }
  }
}
```

Merge the `lookinside` entry into the existing `mcpServers` object if the file already contains other servers. Quit and reopen Claude Desktop after saving it.

See the [MCP guide for connecting local servers](https://modelcontextprotocol.io/docs/develop/connect-local-servers) for configuration and log locations.

### Other clients

Cursor, Windsurf, VS Code, and other MCP clients can use the same shim. Add a local `stdio` server named `lookinside` with:

- **Command:** `node`
- **Arguments:** `/Applications/LookInside.app/Contents/Resources/MCP/lookinside-mcp-shim.mjs --socket /Users/<username>/Library/Application Support/LookInside/Host/run/lookinside-host-mcp.sock`
- **Environment:** none

The surrounding JSON or settings UI differs by client, so use that client's local `stdio` server format.

## Verify the connection

After restarting or opening a new client session, ask the agent:

> Use LookInside's `ping` tool to verify that the host bridge is reachable. Do not use a shell command.

A successful response is a JSON result from the host bridge rather than an MCP transport error.

Then verify that the current inspection session is visible:

> Use LookInside's `targets_list` tool. Report the attached targets.

`targets_list` returns an empty list when LookInside is running but has not opened a target. Return to the LookInside launch window, connect to the app, and retry.

## Recommended inspection workflow

Agents get the most reliable results when they follow this order:

1. Call `ping` to verify that LookInside is running.
2. Call `targets_list` and choose a target identifier.
3. Call `hierarchy_reload` if the user navigated, presented a sheet, or otherwise changed the target app since the last read.
4. Use `screenshot_read` without an object identifier for a visual overview.
5. Use `hierarchy_find` when looking for a view class. Prefer it over loading a large complete tree.
6. Use `hierarchy_read` with a bounded `depth`, or scope it to a `rootObjectIdentifier` returned by an earlier call.
7. Call `details_read` before `attributes_read` when inspecting newly discovered object identifiers.
8. Re-find views after a hierarchy refresh. Object identifiers from the previous tree may no longer resolve.

For example:

> Use LookInside to inspect the first attached target. Refresh its hierarchy, take a window screenshot, find visible button views, and summarize each button's frame and title. Do not mutate the app.

## Available tools

| Area | Tools | Purpose |
| --- | --- | --- |
| Connection | `ping`, `targets_list` | Check the host bridge and discover attached apps. |
| Hierarchy | `hierarchy_read`, `hierarchy_find` | Read or search the current view tree. |
| Details | `attributes_read`, `details_read`, `selectors_list` | Inspect properties and available Objective-C selectors. |
| Visuals | `screenshot_read` | Capture the key window or one view as PNG. |
| Refresh | `hierarchy_reload` | Reload the tree after the target UI changes. |
| Mutation | `invoke_method`, `attribute_modify` | Call a zero-argument selector or change a supported attribute in the Debug app. |

The MCP client receives each tool's complete input schema and description when it connects. Let the client use those schemas instead of guessing argument names or value shapes.

## Safety and privacy

- Treat the target app as a development or debugging environment. `invoke_method` and `attribute_modify` can change its state immediately.
- Ask before using mutation tools unless the user explicitly requested the change.
- Prefer `selectors_list` before `invoke_method`; method invocation currently supports zero-argument Objective-C selectors.
- Treat hierarchy, attributes, and screenshots as potentially sensitive app data.
- The MCP shim is local and does not configure credentials. Your AI client still applies its own data-handling and tool-approval policies to any hierarchy, attributes, or screenshots it reads.

## Troubleshooting

| Symptom | What to check |
| --- | --- |
| The client cannot start `lookinside` | Confirm that `node` is installed and the bundled shim passes the `test -x` check above. Official releases include it; a local source build may not. |
| `ping` cannot connect | Launch the same LookInside app bundle referenced by the MCP command, then retry. |
| `targets_list` returns `[]` | Run the target app and connect to it from the LookInside launch window. Opening LookInside alone is not enough. |
| Results describe the previous screen | Call `hierarchy_reload`, then locate the views again instead of reusing old object identifiers. |
| `attributes_read` reports uncached details | Call `details_read` for that object identifier, then retry. |
| A screenshot is blank | Capture a descendant that performs the drawing; upper window, theme-frame, or hosting views can render no pixels by themselves. |
| The server was added but does not appear | Restart or open a new MCP client session and use the client's MCP status command or panel. |
