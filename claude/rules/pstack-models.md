# pstack model configuration. One line per role. Delete a line to fall back to the skill default.
# Managed by guisaliba/agents apply.sh: edit claude/rules/pstack-models.md in that repository, not this copy.
# Do not run /pstack:setup-pstack. It accepts only detected Claude models and would drop every go/ entry.
# `inherit-parent` or `auto` as a value: the role runs on the parent chat model (omit Agent `model`).
# `<model> <effort>` (for example `opus high`) runs a Claude subagent on the Claude Pro plan.
# `go/<alias>` runs an OpenCode Go worker through `go-worker`. See ~/.claude/rules/pstack-go.md.
# budget: large (xhigh)
feature, refactoring: go/kimi-k2.7-code
bug-fix: go/kimi-k2.7-code
perf-issue: go/glm-5.3
hillclimb: go/deepseek-v4.1-flash
judgment and prose: opus xhigh
hardest tasks: opus xhigh
how explorer: go/deepseek-v4.1-flash
how explainer: opus high
why investigators: go/deepseek-v4.1-flash
why synthesizer: opus high
reflect tooling: go/deepseek-v4.1-flash
reflect judgment, divergent, synthesizer: opus high
arena runners: inherit-parent, go/kimi-k3.1, go/glm-5.3
arena cross-judge pool: go/kimi-k3.1, go/glm-5.3
swarm workers: go/deepseek-v4.1-flash
architect runners: inherit-parent, go/kimi-k3.1, go/glm-5.3
interrogate reviewers: go/kimi-k3.1, go/glm-5.3, go/gpt-6-luna, go/deepseek-v4.1-flash
