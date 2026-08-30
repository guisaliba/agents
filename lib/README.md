# Shared Helper

`agent_stack.py` is the standard-library-only helper used by `apply.sh` and
`test.sh`. It centralizes safe file writes, environment assignment handling,
skill-manifest validation, JSON and TOML checks, and managed runtime merges.

The helper does not run external commands and is not installed into the
workstation. Validate it through:

```sh
./test.sh --repo-only
python3 -m py_compile lib/agent_stack.py
```
