# RTK

RTK is the command-output compaction layer for the agent harness. Apply
installs its OpenCode integration with:

```sh
rtk init -g --opencode
```

The OpenCode plugin is installed at:

```text
~/.config/opencode/plugins/rtk.ts
```

Useful commands:

```sh
rtk rewrite "git status --short"
rtk gain
rtk <command>
```

RTK is installed live. Its payload is not vendored in this repository.
