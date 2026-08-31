# Linear MCP

`apply.sh` configures the remote Linear MCP server as `mcp.linear`:

```text
https://mcp.linear.app/mcp
```

The server uses OpenCode OAuth. Authenticate it with:

```sh
opencode mcp auth linear
```

Verify the connection with:

```sh
opencode mcp list
opencode mcp debug linear
```

Use Linear MCP for hosted workspace objects such as issues, projects, teams,
cycles, documents, releases, and comments. Keep local repository edits and Git
operations in the checkout with normal Git tools.
