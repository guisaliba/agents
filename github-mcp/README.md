# GitHub MCP

`apply.sh` configures the official remote GitHub MCP server in the global
OpenCode configuration:

```json
{
  "type": "remote",
  "url": "https://api.githubcopilot.com/mcp/",
  "enabled": true,
  "oauth": false,
  "headers": {
    "Authorization": "Bearer {file:~/.config/opencode/secrets/github-mcp-pat}",
    "X-MCP-Toolsets": "context,repos,issues,pull_requests,actions"
  }
}
```

## Token

The token file is machine-local:

```text
~/.config/opencode/secrets/github-mcp-pat
```

Apply creates an empty `0600` file and never replaces its contents. Store only
the PAT in the file. Do not add the token, quotes, or `Bearer` to Git or to
`opencode.json`.

## Verify

```sh
opencode mcp list
opencode mcp debug github
```

Use GitHub MCP for hosted GitHub objects. Use local `git` for the worktree and
Git graph. Use `gh` when MCP does not provide the required operation or detail.
