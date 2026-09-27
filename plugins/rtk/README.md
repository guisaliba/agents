# RTK

RTK remains available as a command-output compaction CLI, but its OpenCode
plugin is disabled. No released RTK version currently provides the complete,
verified V2 `execute.before` contract.

```sh
rtk rewrite "git status --short"
```

Do not install the current V1 plugin at:

```text
~/.config/opencode/plugins/rtk.ts
```

Useful commands:

```sh
rtk rewrite "git status --short"
rtk gain
rtk <command>
```

Re-enable it only after a stable RTK release proves the V2 default export,
shell filtering, exit-code 3 handling, timeout rejection, missing-binary
fail-open behavior, macOS/Linux lookup, and a real stable V2 loader test.
