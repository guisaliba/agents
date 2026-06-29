---
name: auto-pr-review
description: Work through reviewer comments on an already-opened pull request. Read every review comment (e.g. from GitHub Copilot or a human reviewer), judge each one against the codebase and the project's own docs/conventions, implement the valid ones as atomic commits, reply to each thread citing the fix commit (or a rejection rationale), resolve the threads, then @-mention the reviewer to request another pass. Use when the user says things like "address the PR review comments", "resolve Copilot's comments", "go through the review feedback on the PR", or "iterate on the opened PR".
argument-hint: "PR number or URL (optional; defaults to the current branch's PR)"
---

# Address PR Review

A loop for the post-open review phase of a pull request: a reviewer (an AI assistant,
a teammate, or both) leaves comments on the open PR; you triage them
honestly, fix the valid ones, close the loop on every thread, and ask for a
re-review. The point is **judgment plus follow-through** — not blindly applying
every suggestion, and not leaving threads dangling.

## When to use this skill

- A PR is already open and a reviewer (often Copilot) has left comments.
- The user asks to "address", "resolve", "respond to", or "go through" review
  feedback, or to "ask Copilot to re-review".
- You're iterating on an opened PR rather than authoring fresh changes.

## Prerequisites

- `gh` is authenticated and the repo has a remote on GitHub.
- You're on the PR's branch (or know its number). Derive context with:

```sh
gh pr view --json number,headRefName,baseRefName,url
```

Set `REPO=<owner>/<name>` and `PR=<number>` for the snippets below
(`gh repo view --json nameWithOwner -q .nameWithOwner` gives `REPO`).

## Step 1 — Collect the feedback and the OPEN conversations

Reviewers leave feedback in three places. Read all three so nothing is missed,
and identify which review threads are still **unresolved** — those are the ones
to act on (a thread someone already resolved is done; don't reopen it without
reason). The GraphQL query in Step 5 returns each thread's `isResolved`.

```sh
# Review summaries (the overall "Copilot reviewed N files" body, verdicts)
gh api repos/$REPO/pulls/$PR/reviews \
  --jq '.[] | "--- \(.user.login) [\(.state)] ---\n\(.body)\n"'

# Inline review comments (the actionable ones — note id, path, line, in_reply_to_id)
gh api repos/$REPO/pulls/$PR/comments --paginate \
  --jq '.[] | "id=\(.id) by \(.user.login)\n\(.path):\(.line // .original_line)  reply_to=\(.in_reply_to_id // "-")\n\(.body)\n"'

# Top-level PR (issue) comments
gh api repos/$REPO/issues/$PR/comments --jq '.[] | "\(.user.login): \(.body)\n"'
```

Capture each inline comment's **id**, **path:line**, and **body** — you'll need
the id to reply and resolve.

## Step 2 — Triage each comment (judge accept vs reject, don't obey)

For **every** unresolved comment, decide *accept* (implement it) or *reject*
(won't implement, with a reason) by checking it against:

- the actual code at the cited `path:line` (read it — reviewers can be wrong or
  stale),
- the project's source of truth: `CONTEXT.md` / glossary, `docs/SPEC.md`,
  `docs/adr/*`, any `docs/contracts/*`, and the repo's conventions,
- the PR's own intent and scope.

Rules of thumb:

- **Group by root cause.** Several comments often share one fix (e.g. "not
  scoped to X" repeated at 3 call sites → one parameter + 3 call-site edits).
- **Reject with a reason** when a suggestion is wrong, out of scope, already
  handled, or contradicts an ADR/spec. A clear rationale is a valid outcome.
- **Don't expand scope.** Pre-existing issues the comment didn't raise → note,
  don't fix here.
- Keep a short list: `{comment_id, verdict, plan}`.

## Step 3 — Implement the valid fixes

- Follow the repo's commit/branch conventions (read `AGENTS.md`/`CONTRIBUTING`).
- Add or adjust **tests** when a fix warrants it — a regression test that
  directly proves the reviewer's concern is the strongest reply.
- **Verify**: run the test suite / build / typecheck. Don't reply "fixed" on red.

## Step 4 — Commit and push

One atomic commit per logical fix (or one cohesive commit if the comments share
a root cause), referencing the review. Push to the PR branch:

```sh
git add -A && git commit -m "fix(scope): <summary> (PR #$PR review)"
git push
```

Note the resulting commit SHA(s) — you'll cite them in the replies.

## Step 5 — Reply to and resolve every thread, one by one

Go thread by thread. Each reply states the verdict explicitly: **accepted** —
fixed in `<sha>`, with a one-line how; or **rejected** — the reason. Then
resolve that thread before moving to the next, so the PR's unresolved count ends
at zero (every conversation has an answer).

```sh
# Reply to an inline review comment thread
gh api -X POST repos/$REPO/pulls/$PR/comments/<COMMENT_ID>/replies \
  -f body="Fixed in <sha> — <one-line note>."
#   …or for a rejection:
#   -f body="Not applying: <reason grounded in the code/spec/ADR>."
```

Resolving requires the thread's GraphQL node id (map it from the inline
comment's `databaseId`):

```sh
# List threads with their node id + first comment's databaseId + resolved state
gh api graphql -f query='
query($owner:String!,$name:String!,$pr:Int!){
  repository(owner:$owner,name:$name){
    pullRequest(number:$pr){
      reviewThreads(first:100){ nodes{ id isResolved comments(first:1){ nodes{ databaseId } } } }
    }
  }
}' -F owner=<owner> -F name=<name> -F pr=$PR \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[] | "\(.comments.nodes[0].databaseId) \(.id)"'

# Resolve a thread by its node id
gh api graphql -f query='
mutation($t:ID!){ resolveReviewThread(input:{threadId:$t}){ thread{ isResolved } } }' \
  -F t=<THREAD_NODE_ID>
```

Only resolve a thread once you've actually addressed it (fixed and pushed, or
replied with a rejection rationale the user/reviewer can see).

## Step 6 — Ask for a re-review

Post one PR comment that @-mentions the reviewer so it runs another pass
(Copilot re-reviews when mentioned). **Explain the changes if there were any**;
if everything was rejected (no changes), say that and why, and still ask for the
re-review:

```sh
# When changes were made:
gh pr comment $PR --body "@copilot all N comments were addressed in <sha> (each thread replied to + resolved):
1. <comment> → <fix>
...
Tests are green. Please re-review the latest changes."

# When nothing changed (all rejected):
gh pr comment $PR --body "@copilot reviewed all N comments; none were applied — <brief reasons, grounded in the code/spec>. No code changed. Please take another look and let me know if you disagree."
```

For a human reviewer, `@`-mention them instead, or re-request via
`gh pr edit $PR --add-reviewer <login>`.

## Close the loop

A re-review may surface **new** comments — if so, run this skill again from
Step 1. Stop when the reviewer signs off (or the user is satisfied). Report a
crisp summary: which comments were fixed (with commits), which were rejected
(with reasons), and the test status.
