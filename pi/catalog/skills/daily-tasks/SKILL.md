---
name: daily-tasks
description: Manage the private daily task workflow in the brain vault. Use when the user starts or closes a workday, gives a daily to-do list, asks what to work on next, adds or completes a task, or asks for the current plan.
---

# Daily Tasks

Maintain one private task record per active day. Keep commitments explicit,
small, and recoverable across devices.

## Locate and synchronize

1. Resolve the current Git root. Continue only when it contains the initialized
   `journal` repository and `journal/AGENTS.md`.
2. Read `journal/AGENTS.md` before task data.
3. Resolve this skill's base directory from the loaded skill metadata, then run:

   ```sh
   <skill-base>/scripts/journal-task-sync pull <brain-root>
   ```

4. Stop on a sync error. Preserve all local files and report the exact blocker.

Read only `journal/tasks/preferences.md` and dated Markdown files below
`journal/tasks/`. A dated journal entry at `journal/YYYY-MM-DD.md` is private
and out of scope unless the current user prompt explicitly asks to read it.

## Choose the branch

- **Start day:** The user gives tasks, says to start work, or asks for help to
  plan today.
- **Change state:** The user adds, completes, drops, or defers a task.
- **Show plan:** The user asks what is open or what to do next.
- **Close day:** The user asks to review or close the workday.

Use the machine's local date. The daily path is
`journal/tasks/YYYY-MM-DD.md`.

## Start day

1. Read preferences and the newest earlier task file, if they exist.
2. Search ai-memory only for work context relevant to tasks the user named.
   Treat recalled work as a suggestion, not a commitment.
3. Ask only for facts that block a useful order, such as a hard deadline or
   available time. A clear list in the current prompt is enough confirmation;
   do not ask the user to repeat it.
4. Suggest at most three focus outcomes, then order the supporting tasks.
5. Confirm any carry-forward item. In the old file, move it from `Open` to
   `Deferred` and append `-> [[tasks/YYYY-MM-DD|carried to YYYY-MM-DD]]`.
   In today's `Open`, append `_(from [[tasks/YYYY-MM-DD|YYYY-MM-DD]])_`.
6. Create today's file only after the commitments are confirmed.

Use this exact shape:

```markdown
---
date: YYYY-MM-DD
type: daily-tasks
---
# Tasks: YYYY-MM-DD

## Focus

## Open

## Completed

## Deferred

## Notes
```

Use `- [ ]` in `Open`, `- [x]` in `Completed`, and unchecked items with a
destination or reason in `Deferred`.

## Change state

Edit the current daily file directly. Move completed items to `Completed` and
preserve their text. Put deferred or dropped items in `Deferred` with a short
reason or destination. Add unplanned completed work to `Completed` so the day
record stays accurate.

## Show plan

Do not edit. Report the focus and open tasks in their current order. Recommend
one next action using the task order, explicit deadlines, and recorded
preferences. State when the file does not contain enough information.

## Close day

Review each open item with the user. Move it to `Completed` or `Deferred`, add
only a short useful note, and leave tomorrow's file absent. The next start-day
branch handles rollover.

## Preferences

Update `journal/tasks/preferences.md` only when the user explicitly states or
corrects a planning preference. Keep current preferences concise. Do not infer
a durable preference from one difficult day or from journal prose.

## Publish

After each task or preference mutation, run:

```sh
<skill-base>/scripts/journal-task-sync publish <brain-root>
```

This daily-task invocation authorizes that task-only commit and push. The
helper must publish the private journal before the public parent gitlink. On
failure, preserve the edits and report that remote state is not yet current.

The workflow is complete when the requested task state is visible in the
private Markdown file and the publish helper succeeds. A read-only show-plan
request is complete after the current plan and one next action are reported.
