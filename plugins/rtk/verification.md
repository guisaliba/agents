# RTK V2 adapter verification

Verified on 2026-09-30.

## Source and release checks

- Project main SHA before the branch: `ce7bd43b2e775dacdf17cb009bbd890b334ffb4`.
- RTK PR #4187 remained open. The latest stable RTK release checked was
  `v0.50.0`, released on 2026-09-24.
- The pinned plugin has Git blob SHA
  `a6da9a687e4d2c886eaed8ac366a2940faac871e` and SHA-256
  `601875c939db05c58d86d7be788f9c329c9de490faf09f30c97703cc271d4339`.
- The `v0.50.0` macOS arm64 release archive matched the SHA-256 in RTK's
  `checksums.txt`: `fe54761a9950266e3a78ddb66a8af5e067251169da306a288e0751de63d836fe`.
- The existing local RTK `0.38.0` is stable and rewrites
  `git status --short` to `rtk git status --short` with exit code 3. Apply keeps
  a compatible installed CLI. The real loader smoke test used RTK `0.50.0`.

## Checks

These checks passed:

```text
bash -n apply.sh test.sh
./test.sh --repo-only
```

The repo-only suite includes the isolated installer fixtures and two separate
Bun test processes. The rewrite tests cover exit codes 0 and 3, unchanged or
empty output, errors, launch failure, signal termination, timeout, command
validation, lookup, cache behavior, and real event mutation.

The real runtime smoke test passed with:

```text
OpenCode: opencode v2.0.18
RTK:      rtk 0.50.0
Platform: macOS arm64
```

To repeat it, point the variables at stable binaries and a private temporary
directory:

```sh
TMPDIR=<private-temporary-directory> \
OPENCODE_BIN=<path-to-opencode> \
RTK_BIN=<path-to-rtk> \
python3 plugins/rtk/smoke-test.py
```

The script used an isolated `HOME`, config directory, local Git workspace, and
local OpenAI-compatible test provider. It did not read the normal OpenCode
config or use a provider credential. Its shell permission rules asked by
default and allowed only the original and rewritten test commands. It did not
use `--auto`.

The real tool call and output were:

```text
before: git status --short --branch
after:  rtk git status --short --branch
output: * No commits yet on main
        ?? smoke.txt
```

The smoke test returned `RTK_SMOKE_COMPLETE`. It also reported the expected
plugin SHA-256, the `shell` tool name, and three local provider requests. The
OpenCode loader and shell tool ran. The RTK hook changed the command before the
shell tool executed it.

## Project plugin ID probe

An isolated OpenCode `2.0.18` run tested a project plugin beside the global RTK
adapter:

| Project plugin ID | Project setup ran | Global RTK rewrite ran |
| --- | --- | --- |
| `project.test` | Yes | Yes |
| `rtk` | No | Yes |

The smoke script can repeat this check with `RTK_SMOKE_PROJECT_PLUGIN_ID` set to
each ID. This confirms that a project plugin with the pinned global ID does not
initialize alongside the global adapter.

## Limits

- The runtime test ran on macOS arm64. It did not run on Linux or Windows.
- The test uses a local test provider, not an external model provider. It proves
  OpenCode plugin loading, hook execution, permission checks, and shell execution.
- The full workstation mode of `./test.sh` and a live `./apply.sh` were not run.
  The installer was tested with temporary homes. No client or server config was
  changed.
