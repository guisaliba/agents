# Claude Code cloud sessions

Run the pstack workflow in Claude Code cloud sessions (claude.ai/code, the
Claude app's Code tab, `claude --cloud`) with no machine of your own.

## How it connects

A cloud session has two independent parts:

- **Repository**: the project you work on. The session clones it.
- **Environment**: the VM configuration. Its setup script installs this agent
  stack into the VM, for every repository you pick with that environment.

So the stack lives in the environment, not in each repository. Pick the
environment below with any repository, and the session has pstack, the role
table, and the OpenCode Go workers.

## What the cloud profile installs

`cloud/setup.sh` clones this repository to `/opt/agents` and runs
`apply.sh --cloud`, which installs:

- `~/.claude/CLAUDE.md` and the pstack rules (`pstack-models.md`,
  `pstack-workers.md`), with Opus as the main model;
- the pstack plugin;
- the worker profile (`~/.claude-worker`) and `claude-worker`, linked into
  `/usr/local/bin`;
- RTK, wired to both profiles;
- `bubblewrap` and `socat`, for the read-only worker sandbox.

Not in the cloud profile: ai-memory (a cloud VM has no systemd, and nothing in
it stays after the session) and the Bash `claude` wrapper.

## Set up the environment (once)

At claude.ai/code, open the environment selector under the message box. Add an
environment, or open the settings of an existing one.

1. **Network access**: **Trusted** is enough. Its default list includes
   `claude.ai` and the GitHub hosts that the RTK installer uses, and a
   network-secret host (`opencode.ai`, step 2) can be reached at every access
   level. **Full** also works. With the environment-variable fallback below,
   use **Full**, or **Custom** with `opencode.ai` plus the default list.

2. **Network secrets** > **Add secret**, type **Bearer**:
   - **Name**: `OpenCode Go`
   - **Allowed websites**: `opencode.ai`
   - **Custom headers**, two rows, both with your OpenCode Go key as the value:
     - `Authorization`, prefix `Bearer`
     - `x-api-key`, no prefix

   Claude Code sends the worker key in both headers (measured with
   `apiKeyHelper`), so the secret must set both. Inside the VM, the worker
   sends the placeholder `network-secret-placeholder`, and the agent proxy
   puts the real key on the request after it leaves the VM.

3. **Setup script**: paste the content of [`setup.sh`](setup.sh).

4. Save.

### Fallback: the key as an environment variable

If the network secret does not reach the provider (`claude-worker doctor
--live` fails on the live model list or the live run), put the key in the
environment's **Environment variables** instead:

```text
OPENCODE_API_KEY=<your OpenCode Go key>
```

`claude-worker-key` uses it before the network-secret placeholder. Anyone who
can use the environment can read its variables, and every command in the
session can read the key.

## Check a session

Start a session with the environment and any repository, then ask Claude to
run:

```bash
claude-worker doctor --live
```

Expected: every check is `ok`, and the live run replies `READY`. Then try
`/pstack:poteto-mode` or `/pstack:arena` on a small task.

## Update to a newer `main`

The setup script runs once per environment snapshot, and a snapshot is kept
for about seven days. To pick up a new `main` at once, edit the setup script
(any change, such as a comment with the date) and save.
