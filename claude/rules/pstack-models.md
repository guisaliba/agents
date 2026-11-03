# pstack model configuration. One line per role. Delete a line to fall back to the skill default.
# Managed by guisaliba/agents apply.sh. Edit claude/rules/pstack-models.md there. Do not run /pstack:setup-pstack.
# `<model> <effort>` runs a Claude subagent on the Claude Pro plan. `worker/<alias>` runs claude-worker (rules/pstack-workers.md).
# budget: large (xhigh)
feature, refactoring: worker/kimi-k2.7-code
bug-fix: worker/kimi-k2.7-code
perf-issue: worker/glm-5.3
hillclimb: worker/deepseek-v4.1-flash
judgment and prose: opus xhigh
hardest tasks: opus xhigh
how explorer: worker/deepseek-v4.1-flash
how explainer: opus high
why investigators: worker/deepseek-v4.1-flash
why synthesizer: opus high
reflect tooling: worker/deepseek-v4.1-flash
reflect judgment, divergent, synthesizer: opus high
arena runners: inherit-parent, worker/kimi-k3.1, worker/glm-5.3
arena cross-judge pool: worker/kimi-k3.1, worker/glm-5.3
swarm workers: worker/deepseek-v4.1-flash
architect runners: inherit-parent, worker/kimi-k3.1, worker/glm-5.3
interrogate reviewers: worker/kimi-k3.1, worker/glm-5.3, worker/gpt-6-luna, worker/deepseek-v4.1-flash
