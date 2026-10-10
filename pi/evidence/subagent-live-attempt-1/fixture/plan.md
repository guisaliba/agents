# Architecture and acceptance plan

## Decision and evidence

Use one small `clamp(value, low, high)` function in `clamp.py`. Architecture means the structure of the code and its interfaces. Explicit comparisons make the required error check and each return path clear.

Facts from `contract.md`:
- Line 2 requires a Python `clamp(value, low, high)` function.
- Line 3 requires `ValueError` when `low > high` and the applicable bound for a value outside the interval.
- Line 4 prohibits dependencies, network access, credentials, commits, and changes outside this fixture.

The assigned scope also requires the original value for a value inside the interval. The interval includes both bounds. No existing implementation or test runner was present in the initial directory listing; only `contract.md` and `fixture.json` were present.

## Smallest design

1. Check `low > high` first; raise `ValueError` if true.
2. If `value < low`, return `low`.
3. If `value > high`, return `high`.
4. Otherwise, return `value`.

Use the Python standard-library `unittest` runner for focused tests. This adds no dependency. No command-line interface, input conversion, configuration, or additional validation is required.

Alternative: nested `min` and `max` calls can shorten the expression, but still need the separate bounds check and make the return paths less explicit. Do not use this alternative. A package or class would add structure without a contract benefit; do not add either.

## Ordered work and acceptance

1. **Coder: add `clamp.py` and focused tests.** Tests must cover a value below the interval, above it, inside it, exactly at each bound, and equal bounds. Test reversed bounds with values below, inside, and above the reversed pair to confirm that rejection comes first. Include a negative-value case and a finite fractional-value case. Acceptance: all specified outputs match; all reversed-bound cases raise `ValueError`.
2. **Coder: run focused checks.** Use `python -B -m unittest discover -v` with a discoverable `test_*.py` file. Acceptance: the command exits successfully and reports the executed tests. The `-B` option avoids bytecode output files. Inspect the source to confirm there are no external imports or added features.
3. **Reviewer: inspect the completed implementation and tests.** Report defects in `review.md`; do not repair them. Acceptance: findings identify source locations and contract impact, or report that no defect was found in the reviewed scope.
4. **Writer: document the verified source.** Document import, call examples, reversed-bound behavior, and the exact test command in `README.md`. Acceptance: examples agree with the implementation and contract.
5. **Coordinator: verify deliverables and repeat focused tests.** Confirm the implementation, tests, and required reports exist; inspect their contents. Acceptance: report actual command results and any remaining limitation.

## Scope boundaries and assumptions

Assumption: callers provide mutually comparable values and bounds. Special rules for NaN, incompatible types, or custom comparison behavior are outside the assigned contract. Do not add them. End-to-end infrastructure is not needed for this isolated function; direct import and focused unit tests exercise its complete public interface. The other assigned fixture outputs and visual artifact are independent deliverables, not new clamp behavior.

This file is a plan only. No implementation or test result is claimed here.
