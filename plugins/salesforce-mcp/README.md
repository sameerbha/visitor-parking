# Salesforce MCP (Codex plugin)

This plugin scaffolds a place to register a Salesforce MCP server with Codex.

## What to fill in

- `./.mcp.json`: set the `command`/`args` to whatever Salesforce MCP server you use (Node/Python/binary) and populate the needed env vars.
- `./.codex-plugin/plugin.json`: replace the remaining `[TODO: ...]` fields (name, description, icons, etc.).

## Typical server choices

If you already have a Salesforce MCP server command, drop it into `./.mcp.json`.

Examples (pick one and update to match your environment):

- Node (local package): `command: "node"`, `args: ["./path/to/server.js"]`
- Node (npx): `command: "npx"`, `args: ["-y", "[TODO: npm-package-name]"]`
- Python: `command: "python3"`, `args: ["-m", "[TODO: python_module]"]`

## Credentials

The env vars in `./.mcp.json` are placeholders. Update them to whatever your MCP server expects (OAuth, JWT, username/password+token, etc.).

