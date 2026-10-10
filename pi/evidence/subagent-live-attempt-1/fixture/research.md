# Local brief: contract.md and fixture.json

Read-only brief. The only sources are `contract.md` and `fixture.json`, in the fixture root.
No network access. Inspection date: 2026-10-10.

## 1. File inventory (observed)

| File | Bytes | Lines | SHA-256 |
| --- | --- | --- | --- |
| `contract.md` | 231 | 4 | `542cb78e378c92b21098b420d6675a789b5442216cd0f8826d85525df8c961b2` |
| `fixture.json` | 48 | 1 | `6f318153d256d64949fcd3ac70729f8e456dc05c577d464c5e71f230002ac284` |

Both files end with one newline character (0x0a).

## 2. contract.md (observed)

- `contract.md:1` — `# Fixture contract`. The title line. The file is the task contract.
- `contract.md:2` — `Add a Python clamp(value, low, high) function.` The line gives the function
  name, the signature, and three parameters: value, low, high.
- `contract.md:3` — `Reject low > high with ValueError. Return low/high for values outside the
  interval.` The line gives two rules:
  - Rule A: if low > high, raise ValueError.
  - Rule B: if the value is outside the interval, return the nearest bound.
- `contract.md:4` — `No dependencies, network, credentials, commits, or changes outside this
  fixture.` The line gives five restrictions:
  1. no dependencies
  2. no network
  3. no credentials
  4. no commits
  5. no changes outside this fixture

## 3. fixture.json (observed)

- `fixture.json:1` — the whole file is one JSON object on one line:
  `{"label":"AUTOMATIC-TEAM-TEST","items":[2,3,5]}`
- Size is 48 bytes: a 47-byte JSON body plus one newline byte.
- A JSON parse gives a dict with two keys, in this order: `label`, then `items`.
- `label` is the string `AUTOMATIC-TEAM-TEST`. Length is 19 characters.
- `items` is the array `[2, 3, 5]`. It has three elements. Each element is an int.
- The exact integer sum of `items` is 10 (2 + 3 + 5 = 10).

## 4. Reading of the exact wording (inference, not stated by a source)

- The test in rule A is strict: `contract.md:3` writes `low > high`. So `low == high` is legal.
- Rule B uses the word `outside`. So a value equal to a bound is not outside.
- `contract.md` gives no rule for the in-range case. The plain reading is: return the value
  unchanged.
- `contract.md` gives no error message text, no type information, and no rule for NaN.

## 5. Relation between the two files (observed)

- `contract.md` does not mention `fixture.json`, and `fixture.json` does not mention
  `contract.md`. The two files have no cross-reference.
- Therefore `fixture.json` is independent data, and `contract.md` is the only rule source for
  `clamp()`.

## 6. Limits of this brief

- This brief covers `contract.md` and `fixture.json` only. No other source was read.
