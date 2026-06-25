# Salesforce (via MCP)

Use this skill when you want to read/write Salesforce data through the configured Salesforce MCP server.

## Prereq

This plugin must have a working MCP server entry in `../.mcp.json` under `mcpServers.salesforce`.

## What I can do

- Query objects (Accounts, Contacts, Opportunities)
- Create/update records
- Search for records by email/name
- Summarize pipeline and recent activity

## Prompts that work well

- "Find the Account for Acme and list the last 10 Opportunities with stage + amount."
- "Create a Contact for Jane Doe (jane@acme.com) under the Acme Account."
- "For the last 30 days, summarize closed-won Opportunities by owner."

