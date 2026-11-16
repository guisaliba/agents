# Write seats in Docker Sandboxes

## Context

A pstack write seat (implementation, arena runner, architect runner, swarm
worker that edits) runs a non-Claude model with `acceptEdits` and Bash. On the
host, that process can read and change everything that your user can. Docker
Sandboxes runs a coding agent in a microVM with its own Linux kernel, its own
Docker Engine, and a host-side network proxy
([Docker Sandboxes](https://docs.docker.com/ai/sandboxes/),
[Architecture](https://docs.docker.com/ai/sandboxes/architecture/)).

This document records the design that puts each write seat in its own
microVM, the facts it depends on, and the hypotheses that a real run must
still prove. A fact has a source (a documentation link or a measurement). A
hypothesis has the command that confirms it.

## Decisions

| Item | Decision | Reason |
| --- | --- | --- |
| Write seats | One new microVM per seat, in clone mode, removed after the seat. | The seat changes only a private clone. The coordinator gets the result through Git. |
| Read-only seats | Keep the Claude Code sandbox (phase 1). | That sandbox already denies writes to the checkout and blocks the network. A microVM per read-only seat is phase 2, after phase 1 is proven. |
| Coordinator (Opus) | Stays on the host. | See [Rejected alternatives](#rejected-alternatives). |
| Host without `sbx` | Run the seat on the host and print `warning: isolation none`. | Your choice. `CLAUDE_WORKER_ISOLATION=sbx` makes it a failure instead. |
| Cost | Local sandboxes only. | Fact: the `sbx` CLI and local sandbox compute are free; cloud sandboxes are pay-as-you-go ([FAQ](https://docs.docker.com/ai/sandboxes/faq/)). |

## How a sandboxed write seat runs

The coordinator does not change how it launches a seat. `claude-worker run`
does these steps:

1. **Create.** `sbx create --clone --name cw-<id> --pull missing --cpus 2
   --memory 4g claude <main checkout>`.
   - Fact: clone mode gives the agent a private Git clone, mounts the host
     repository read-only at `/run/sandbox/source`, and adds a
     `sandbox-<name>` remote on the host
     ([Use Git with sandboxes](https://docs.docker.com/ai/sandboxes/workflows/git/)).
   - Fact: clone mode must start from the main checkout, not from a linked
     worktree, and the clone follows the ref that the main checkout has
     checked out ([Usage, Clone mode](https://docs.docker.com/ai/sandboxes/usage/)).
     So `claude-worker` passes the main checkout, then moves the clone to the
     seat commit in step 3.
   - Fact: without `--memory`, a sandbox gets 50% of host memory
     ([sbx create](https://docs.docker.com/reference/cli/sbx/create/)). A panel
     runs several seats at once, so the default here is 2 CPUs and 4 GiB.
2. **Network.** `sbx policy allow network cw-<id> <provider host>`.
   - Fact: a rule with a sandbox name applies to that sandbox only, and a deny
     rule wins over an allow rule
     ([Policies](https://docs.docker.com/ai/sandboxes/security/policy/)).
3. **Sync.** In the clone: `git fetch <source> <worktree HEAD>` and
   `git checkout -B claude-worker-seat <worktree HEAD>`. The seat starts at the
   commit of its worktree, also when only that worktree has the commit.
4. **Run.** `sbx exec -i -w <clone> --env-file <file> cw-<id> claude -p ...`
   with the same model, tools, and permission mode as a host write seat.
   - Fact: the host `~/.claude` is not in the sandbox
     ([Claude Code agent](https://docs.docker.com/ai/sandboxes/agents/claude-code/)).
     So the worker contract goes in with `--append-system-prompt`, the
     provider settings (`env` block of `~/.claude-worker/settings.json`) go in
     the env file, and an `apiKeyHelper` reads the key from that file's
     `CLAUDE_WORKER_KEY` variable. The env file has mode 600 and is deleted
     after the run.
5. **Collect.** In the clone, the leftover edits become one marked commit.
   On the host: `git fetch sandbox-cw-<id> claude-worker-result`, a
   fast-forward of the worktree, and `git reset --mixed HEAD~1` for the marked
   commit only. Result: the worktree has the commits that the worker made and
   its other edits uncommitted, as after a host run.
   - Fact: the `sandbox-<name>` remote works only while the sandbox runs, and
     `sbx rm` removes it ([Use Git with sandboxes](https://docs.docker.com/ai/sandboxes/workflows/git/)).
     So the fetch comes before the removal.
6. **Remove.** `sbx rm --force cw-<id>`. When step 5 fails, the sandbox stays
   for inspection and standard error names it.

Precondition: the worktree is clean, because clone mode copies commits only.
The coordinator commits the changes that it copies into a worktree
(`claude/rules/pstack-workers.md`). A dirty worktree exits 2.

## Hosts

| Host | Local sandboxes | Expected `isolation` | Evidence |
| --- | --- | --- | --- |
| Mac (Apple silicon, macOS 14+) | Supported. | `sbx` | Fact: [Install](https://docs.docker.com/ai/sandboxes/install/) lists macOS Sonoma 14+ on Apple silicon. Not yet run. |
| Ubuntu 24.04+ on hardware | Supported. | `sbx` | Fact: [Install](https://docs.docker.com/ai/sandboxes/install/) lists Ubuntu 24.04+ with KVM and the `kvm` group. |
| WSL2 Ubuntu | Only with nested virtualization. | `sbx` if `/dev/kvm` exists, else `none` | Fact: inside a VM, "the environment must support nested virtualization" ([Install](https://docs.docker.com/ai/sandboxes/install/)). Hypothesis: WSL2 on your Windows 11 machine exposes `/dev/kvm`. Confirm: `ls -l /dev/kvm` in WSL2. |
| Omarchy (Arch) | Not a supported distribution. | `none` | Fact: the Linux requirement is Ubuntu 24.04 or later ([Install](https://docs.docker.com/ai/sandboxes/install/)). Hypothesis: a manual install from [docker/sbx-releases](https://github.com/docker/sbx-releases) works on Arch with KVM. Not part of this design. |
| Claude Code cloud session | No. | `none` | Fact, measured 2026-11-16 in a cloud session: `ls -l /dev/kvm` gives "No such file or directory", and `/proc/cpuinfo` has no `vmx` or `svm` flag. |

## Install (hosts that support local sandboxes)

```sh
# macOS (Apple silicon)
brew trust docker/tap && brew install docker/tap/sbx
# Ubuntu 24.04+
curl -fsSL https://get.docker.com | sudo REPO_ONLY=1 sh
sudo apt-get install docker-sbx
sudo usermod -aG kvm "$USER"   # then sign out and in

sbx login                       # Docker account (free)
sbx policy set-default balanced # default-deny egress with a baseline allowlist
claude-worker doctor --live
```

Sources: [Install](https://docs.docker.com/ai/sandboxes/install/),
[Policies](https://docs.docker.com/ai/sandboxes/security/policy/). Fact: the
daemon asks for a default policy on first start; `sbx policy set-default`
sets it without a prompt.

`apply.sh` does not install `sbx`: the install needs `sudo`, a group change,
and an interactive `sbx login`.

## Configuration

| Variable | Default | Effect |
| --- | --- | --- |
| `CLAUDE_WORKER_ISOLATION` | `auto` | `auto`: microVM when `sbx ls` works, else host and a warning. `sbx`: microVM or exit 3. `none`: host. |
| `CLAUDE_WORKER_SBX_CPUS` | `2` | CPUs per write-seat sandbox. |
| `CLAUDE_WORKER_SBX_MEMORY` | `4g` | Memory per write-seat sandbox. |

`claude-worker doctor` prints the write-seat isolation of the host. A host
without `sbx` gets a `warn` line, not a failure. `claude-worker doctor --live`
also runs one real write seat in a microVM when `sbx` works.

## Security properties and limits

- The worker changes only its clone. The host files change only through the
  fast-forward that `claude-worker` does, so the coordinator stays the only
  process that writes to your real working tree.
- The worker has no host `~/.ssh`, `~/.aws`, browser profile, or Docker
  contexts. Fact: each sandbox has its own Docker daemon
  ([Architecture](https://docs.docker.com/ai/sandboxes/architecture/)).
- **Limit: the provider key enters the sandbox** (env file, then the
  `apiKeyHelper`). The worker can read it. Docker's credential proxy keeps a
  key outside the sandbox, but the command for a custom host
  (`sbx secret set-custom`) "is hidden from `sbx --help`, and its flags and
  placeholder format may change"
  ([Credentials](https://docs.docker.com/ai/sandboxes/security/credentials/)).
  Move to it when Docker makes it stable. Today, on the host, a worker can read
  the same key file, so this is not a regression.
- Egress: the provider host is allowed for the seat sandbox only. Other hosts
  follow the global policy.
- The microVM protects the host while the seat runs. Its edits still reach
  your worktree after the run. Review the diff before you run code from it (a
  changed build script or test runs on the host).

## Rejected alternatives

- **Coordinator in a sandbox, which starts one sandbox per worker.**
  - Fact: the host `~/.claude` is not in the sandbox
    ([Claude Code agent](https://docs.docker.com/ai/sandboxes/agents/claude-code/)).
    pstack, the role table, and the Pro login do not come in. Each sandbox
    needs its own `/login`.
  - Hypothesis: `sbx` cannot start sandboxes from inside a sandbox, because it
    needs nested virtualization and the host daemon. Docker does not document
    it ([Architecture](https://docs.docker.com/ai/sandboxes/architecture/) does
    not cover it). Confirm: `sbx exec <name> sbx ls`.
  - Consequence: the coordinator would need a host-side broker that starts
    sandboxes for it. A sandboxed process that controls the host `sbx` defeats
    the isolation.
- **Cloud sandboxes for hosts without KVM.** Pay-as-you-go
  ([FAQ](https://docs.docker.com/ai/sandboxes/faq/)); you chose free tier only.
- **Plain Docker containers.** They share the kernel of their Linux
  environment; a sandbox microVM has its own
  ([Why microVMs](https://www.docker.com/blog/why-microvms-the-architecture-behind-docker-sandboxes/)).

## Hypotheses that the first real run must confirm

`claude-worker doctor --live` on a host with `sbx` tests all of them in one
write seat. The fake `sbx` in `test.sh` models the documented contract only.

1. In clone mode, `sbx exec` without `-w` starts in the clone, so `pwd` gives
   the clone path. Docs: commands start in the primary workspace
   ([Usage](https://docs.docker.com/ai/sandboxes/usage/)).
2. `git fetch /run/sandbox/source <commit id>` works for a commit that only a
   linked worktree has.
3. The `claude` in the `claude-code` template supports `-p`,
   `--permission-prompts none`, `--settings`, and `--append-system-prompt`.
4. The per-sandbox network rule lets the worker reach the provider through the
   host proxy.
5. `git fetch sandbox-<name>` on the host reads commits that the worker made.

## Validation

1. On the Mac: install as above, then `./test.sh --repo-only` and
   `claude-worker doctor --live`. Expected: `ok    write-seat isolation:
   Docker Sandboxes microVM (sbx)` and the live sandbox write seat `ok`.
2. In a scratch repository on the Mac: `/pstack:arena add a --json flag to
   <a small script>. 3 candidates.` Expected: the worker seats' meta files
   have `"isolation": "sbx"`, `sbx ls` is empty after the run, and the
   candidate worktrees hold the worker edits.
3. In a cloud session: `claude-worker doctor`. Expected: `warn  write-seat
   isolation: none, because the sbx CLI is not installed`. A write seat prints
   `warning: isolation none` and still succeeds.
