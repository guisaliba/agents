# Session handoff: Pi sub-agent extension selection

## Start here in the next session

The user is ending this session. Transport diagnosis is complete. Start with the user's sub-agent extension requirements, then discuss and select an extension before installation. The user deliberately withheld those requirements until the next session; do not infer them from earlier recommendations.

Read this file, `pi/README.md`, `pi/sources.json`, and the relevant upstream Pi documentation before making changes. This file is the full continuation record for the ai-memory handoff. The handoff must remain pending for the next session; do not consume it while saving it.

## Context

The user selected `openai/gpt-6-luna` at `max` for the YSK observer. The main model remains independent. This choice is settled from the controlled comparison; do not demand live-run equivalence before using it.

The user permits stopping this diagnosis if further work is unlikely to help. Budget: three focused attempts, reassess after each. No paid model requests are needed. The sub-agent extension is next; the user has not yet provided its selection details. Do not select or install one without that discussion.

## Before/after

- Original YSK source: `aliceisjustplaying/pi-you-should-know` at `4ffe3daec322de069bd15e174f23b6d4a5c45419`, unchanged.
- Source copy: `/tmp/pi-port-docs/you-should-know-upstream`.
- Approved private authenticated Pi profile: `/tmp/pi-port-docs/pi-agent`; never read, copy, or link its credentials.
- Selected source packages live under that profile's `port-resources` directory.
- `pi/ysk-config.json` records GPT observer Luna/max; copied as non-secret configuration to the private profile's `you-should-know/config.json`. No earlier configuration existed.
- `pi/launch.py` still requires explicit `--ysk-model` to load YSK. Use Luna. The supported family configuration sets effort to max; the environment model override alone does not select effort.
- `pi/AGENTS.md` and shared instructions are unchanged. Do not run `apply.sh` or `test.sh`. Branch: `feat/pi-local-port`; `pi/` is untracked; no commits.

## Expected behavior and current evidence

The unchanged `GPT default` local protocol test failed again in attempt 1 (`attempt-1.tap`), with `read ECONNRESET`. Earlier retained repeats failed too. The failure is not a real OpenAI request; this fixture uses synthetic credentials and a loopback protocol server.

The fixture at `tests/routing.test.mjs:77` rejects a WebSocket upgrade using `socket.end(HTTP 400)` without an error listener. Attempt 2 confirmed `ECONNRESET` on that server upgrade socket. With an error listener, Pi then completed seven main HTTP requests, an observer HTTP request, and the final main request; every original assertion passed (`attempt-2.tap`).

Attempt 3 handled only the expected `ECONNRESET` on the deliberately rejected upgrade socket; other socket errors still throw. The complete local upstream suite passed 17/17 (`attempt-3.tap`). Every assertion and the runtime extension remained unchanged. The small fixture-only correction is retained in `pi/patches/ysk-routing-fixture.patch`; it is not applied to the installed checkout or loaded by the launcher.

Cause: an expected client disconnect became an unhandled server-side error event in the test fixture. Node documents that emitting an error event without a listener throws: https://nodejs.org/docs/latest-v25.x/api/events.html#error-events . This was not evidence of a broken live observer model or a need for `YSK_MODEL` to repair transport.

Diagnosis is complete and stopped after three attempts. No paid requests, runtime transport change, or upstream publication was made. The original failing evidence remains. The selected observer is independently verified as Luna/max while the main model is Sol (`selected-observer.json`); that check made zero model requests. Next: ask for the user's sub-agent extension context and selection. Do not reopen the settled observer choice or continue transport investigation.

## Next steps and open decisions

- Ask the user for the sub-agent extension context. Catalog first; no installation or architecture choice has been approved yet.
- Follow Pi-native mechanisms. Do not import OpenCode sub-agent roles, model routing, settings, or instructions.
- The eventual extension must support the approved original Learn workflow and YSK child-note relay. Check the actual interfaces before selecting it; do not treat an author's recommendation as user approval.
- Original Learn is `amosblomqvist/learn`, pinned at `7cfd8942f82ab9476e63572387e1fe9bcea5082c`. Full scope was approved, but research execution, visual rendering, and sub-agent integration are not complete.
- Learn visual tools use `globalThis.__pi_interactive_subagents.registerToolExtension`. Its recommended `amosblomqvist/pi-interactive-subagents` extension has not been selected.
- Learn's research tools, researcher/visual-maker model choices, renderer dependencies, and browser execution still require review and relevant approval. Do not install dependencies just because a skill is selected.
- YSK observer calls are direct, tool-free side requests, not sub-agent delegation. Child relay is a separate integration. Keep Luna/max as observer and the main model independently selected.
- MCP selection and durable daily-memory workflow setup remain later tasks. Plannotator is excluded entirely, including its skills and dependencies.
- Preserve OpenCode and the shared configuration, skills, services, and memory identifiers. Ask before shared changes. No permanent services, shared upgrades, remote infrastructure, commits, or upstream publication without approval.
- Do not read secret values, dotenv credential files, SSH/AWS credentials, or auth.json. Never copy or link authentication. Use `/login` if authentication is needed.
- Preserve all real failing evidence. Logger/configuration completion and passing controlled fixtures do not mean the whole port or full Learn workflow is complete.

## Previous stage references

- Learn logger/configuration stage: 12 logger checks; 20 skills loaded; research, renderer execution, and sub-agent interfaces remain deferred.
- Quality: original six important cases detected 18/18 per model. Corrected six silence cases returned none 18/18 per model. Six parallel requests, three repeats; Luna max and Sol low verified on the wire.
- `pi/evidence/ysk-quality-controls/graded-summary.json` records valid comparison results. Keep the original defective controls as inconclusive; do not delete or relabel them.
- User chose Luna/max for cost; do not reopen that choice due to small-sample limitations. No automatic plan/build router and no OpenCode sub-agent architecture migration.
