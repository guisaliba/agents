# Verify in a Fresh Shell, Not the One You Are In

Written by the operator on 2026-09-28 after this lesson cost two rounds of
debugging on the `osarchy` client.

## The rule

When a change affects what a shell resolves, prove it in a **fresh** shell of
**every relevant kind**. Never conclude from the shell you happen to be in.

```sh
env -i HOME="$HOME" USER="$USER" TERM=xterm /bin/bash -lc '<probe>'
env -i HOME="$HOME" USER="$USER" TERM=xterm /bin/bash -ic '<probe>'
```

`env -i` matters. It strips the ambient environment, so the probe measures the
rc files rather than whatever the current session happened to export.

## Why this bit twice

**First time: a function in `~/.profile`.** The forwarding `opencode` function was
placed in `~/.profile`, reachable only because the managed block in
`~/.bash_profile` sources it. A terminal opened *before* the change read the old
`~/.bash_profile` and never saw it. I verified the ordering inside one sourcing
pass and declared it done. The user opened a new terminal and it still failed.

**Second time: a login shell versus a plain terminal.** Bash reads
`~/.bash_profile` for a login shell and `~/.bashrc` for a non-login one. A new
terminal is non-login. `~/.bashrc` sourced `~/.bash_aliases` but never
`~/.profile`, so the function was unreachable there. I tested with `bash -lc`,
concluded it worked, and was wrong about the case the user actually runs.

The fix that satisfies both: put the definition in **one shared file** and source
it from **both** `~/.bashrc` and `~/.bash_profile`.

## The tell that settled it

The failing and the working run printed the *same* `server_url`. The difference
was one path:

```text
broken : data_dir=/home/guisaliba/.local/share/ai-memory        <- the client
working: data_dir=/Users/guisaliba/Library/Application Support/ai-memory  <- the server
```

When two runs look identical, find the field that encodes *where* the work
actually happened. Log the absolute path of the process, the data directory, the
pid, the resolved config. A single absolute path settles "did my change take
effect" faster than ten assertions.

## Apply to

- Shell functions, aliases, and `PATH` additions
- Anything sourced from `~/.bashrc`, `~/.bash_profile`, `~/.profile`, or `~/.zshrc`
- Environment variables a script exports
- Config a daemon reads at start: compare the **running** values against the
  **file**, not the file against itself
- Test fixtures that stub functions: `source` **redefines** them, so a stub
  declared before the source is silently overwritten and the fixture tests
  nothing

## Also

A green suite is not evidence that a feature works. Two of the fixes in this
series shipped green and were dead code, because the fixture called a function
the real entry point never reached, or declared stubs that `source` overwrote.
Drive the test through the same path the real command takes.
