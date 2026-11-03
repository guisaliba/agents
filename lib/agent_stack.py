#!/usr/bin/env python3

import json
import os
import re
import stat
import sys
import tempfile
from pathlib import Path


ENV_ASSIGNMENT = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$")


def parse_env_assignment(line):
    if not line.strip() or line.lstrip().startswith("#"):
        return None

    match = ENV_ASSIGNMENT.match(line)
    if match is None:
        return None

    name, value = match.groups()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1]
    return name, value


def env_assignment_values(path, name):
    path = Path(path)
    values = []
    for line in path.read_text(encoding="utf-8").splitlines():
        assignment = parse_env_assignment(line)
        if assignment is not None and assignment[0] == name:
            values.append(assignment[1])
    return values


def atomic_write_text(path, content, mode, prefix):
    path = Path(path)
    descriptor, temporary_name = tempfile.mkstemp(prefix=prefix, dir=path.parent)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, "w", encoding="utf-8") as temporary_file:
            temporary_file.write(content)
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.replace(temporary_name, path)
    except BaseException:
        try:
            os.close(descriptor)
        except OSError:
            pass
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def guard_regular_file(path, label, allow_missing=True):
    path = Path(path)
    if path.is_symlink():
        raise SystemExit(f"ERROR: {label} must not be a symlink: {path}")
    if path.exists() and not path.is_file():
        raise SystemExit(f"ERROR: {label} must be a regular file: {path}")
    if not allow_missing and not path.exists():
        raise SystemExit(f"ERROR: {label} must be a regular file: {path}")


def ensure_private_file(path, label):
    path = Path(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    path.parent.chmod(0o700)
    guard_regular_file(path, label)
    if not path.exists():
        descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        os.close(descriptor)
    path.chmod(0o600)


def _locate_block(lines, start_marker, end_marker, path, allow_absent):
    starts = [index for index, line in enumerate(lines) if line == start_marker]
    ends = [index for index, line in enumerate(lines) if line == end_marker]
    if not starts and not ends and allow_absent:
        return None
    if len(starts) != 1 or len(ends) != 1 or ends[0] <= starts[0]:
        raise ValueError(
            f"Expected one balanced block {start_marker!r} in {path}; file was not changed"
        )
    return starts[0], ends[0]


def _read_managed_text_target(path, label):
    path = Path(path)
    if path.is_symlink():
        raise ValueError(f"{label} must not be a symlink: {path}")
    if path.exists() and not path.is_file():
        raise ValueError(f"{label} must be a regular file: {path}")
    if not path.exists():
        return "", 0o644
    return path.read_text(encoding="utf-8"), stat.S_IMODE(path.stat().st_mode)


def merge_block(source, target, start_marker, end_marker):
    """Replace or append the marked block from source inside target.

    Unrelated target content is preserved. Return True when target changed.
    """
    source_lines = Path(source).read_text(encoding="utf-8").splitlines()
    bounds = _locate_block(source_lines, start_marker, end_marker, source, False)
    block = source_lines[bounds[0] : bounds[1] + 1]

    text, mode = _read_managed_text_target(target, "Block target")
    lines = text.splitlines()
    target_bounds = _locate_block(lines, start_marker, end_marker, target, True)
    if target_bounds is not None:
        lines = lines[: target_bounds[0]] + lines[target_bounds[1] + 1 :]
    while lines and not lines[-1].strip():
        lines.pop()
    if lines:
        lines.append("")
    lines.extend(block)
    content = "\n".join(lines) + "\n"
    if content == text:
        return False
    Path(target).parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    atomic_write_text(target, content, mode, ".block.")
    return True


def remove_block(target, start_marker, end_marker):
    """Remove one marked block from target. Return True when target changed."""
    target = Path(target)
    if not target.exists() and not target.is_symlink():
        return False
    text, mode = _read_managed_text_target(target, "Block target")
    lines = text.splitlines()
    bounds = _locate_block(lines, start_marker, end_marker, target, True)
    if bounds is None:
        return False
    lines = lines[: bounds[0]] + lines[bounds[1] + 1 :]
    # Do not leave the separator blank line that belonged to the removed block.
    start = bounds[0]
    if start < len(lines) and not lines[start].strip() and (start == 0 or not lines[start - 1].strip()):
        del lines[start]
    while lines and not lines[-1].strip():
        lines.pop()
    content = ("\n".join(lines) + "\n") if lines else ""
    atomic_write_text(target, content, mode, ".block.")
    return True


def _deep_merge(base, patch):
    """Merge patch into base: objects recurse, lists gain missing items, scalars replace.

    Lists are unioned, never replaced, so a managed permission rule joins the
    user's own rules instead of erasing them.
    """
    for key, value in patch.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            _deep_merge(base[key], value)
        elif isinstance(value, list) and isinstance(base.get(key), list):
            for item in value:
                if item not in base[key]:
                    base[key].append(item)
        else:
            base[key] = value
    return base


def merge_json_keys(target, patch_text, label):
    """Deep-merge a JSON object into a JSON object file.

    Keys absent from the patch are preserved, so other installers (ai-memory,
    RTK, the plugin manager) keep their own entries. Return True on change.
    """
    patch = json.loads(patch_text)
    if not isinstance(patch, dict):
        raise ValueError(f"{label} patch must be a JSON object")
    target = Path(target)
    if target.is_symlink():
        raise ValueError(f"{label} must not be a symlink: {target}")
    if target.exists() and not target.is_file():
        raise ValueError(f"{label} must be a regular file: {target}")
    if target.exists():
        text = target.read_text(encoding="utf-8")
        mode = stat.S_IMODE(target.stat().st_mode)
        try:
            data = json.loads(text) if text.strip() else {}
        except json.JSONDecodeError as exc:
            raise ValueError(f"{label} is not valid JSON: {target}: {exc}") from exc
        if not isinstance(data, dict):
            raise ValueError(f"{label} must contain a JSON object: {target}")
    else:
        text, mode, data = "", 0o600, {}
    content = json.dumps(_deep_merge(data, patch), indent=2) + "\n"
    if content == text:
        return False
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    atomic_write_text(target, content, mode, ".json.")
    return True


def _main(argv):
    if len(argv) < 2:
        print("usage: agent_stack.py <operation> ...", file=sys.stderr)
        return 2

    operation = argv[1]
    try:
        if operation == "atomic-write" and len(argv) == 5:
            atomic_write_text(
                argv[2],
                sys.stdin.read(),
                int(argv[3], 8),
                argv[4],
            )
            return 0

        if operation == "env-value" and len(argv) == 4:
            values = env_assignment_values(argv[2], argv[3])
            if not values:
                return 1
            print(values[-1].strip())
            return 0

        if operation == "ensure-private-file" and len(argv) == 4:
            ensure_private_file(argv[2], argv[3])
            return 0

        if operation == "guard-regular-file" and len(argv) == 4:
            guard_regular_file(argv[2], argv[3])
            return 0

        if operation == "merge-block" and len(argv) == 6:
            merge_block(argv[2], argv[3], argv[4], argv[5])
            return 0

        if operation == "remove-block" and len(argv) == 5:
            remove_block(argv[2], argv[3], argv[4])
            return 0

        if operation == "merge-json" and len(argv) == 5:
            merge_json_keys(argv[2], argv[3], argv[4])
            return 0

    except (OSError, ValueError) as exc:  # json.JSONDecodeError is a ValueError
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"usage: agent_stack.py {operation} ...", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv))
