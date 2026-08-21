#!/usr/bin/env python3

import os
import re
import sys
import tempfile
from pathlib import Path


ENV_ASSIGNMENT = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$")
MANIFEST_PROVIDERS = {"local", "upstream", "ai-memory", "plannotator", "cloudflare"}


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


def read_skill_manifest(path):
    path = Path(path)
    rows = []
    names = set()

    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ValueError(f"Cannot read skill manifest {path}: {exc}") from exc

    for line_number, line in enumerate(lines, start=1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue

        fields = line.split("\t")
        if len(fields) != 4:
            raise ValueError(
                f"Invalid skill manifest row at {path}:{line_number}; "
                "expected four tab-separated fields"
            )

        provider, name, source, require_skill_file = fields
        if provider not in MANIFEST_PROVIDERS:
            raise ValueError(
                f"Invalid skill manifest provider at {path}:{line_number}: {provider}"
            )
        if not name or name != name.strip() or any(char.isspace() for char in name):
            raise ValueError(
                f"Invalid skill manifest name at {path}:{line_number}: {name!r}"
            )
        if not source or source != source.strip():
            raise ValueError(
                f"Invalid skill manifest source at {path}:{line_number}: {source!r}"
            )
        if require_skill_file not in {"yes", "no"}:
            raise ValueError(
                f"Invalid skill manifest SKILL.md flag at {path}:{line_number}: "
                f"{require_skill_file}"
            )
        if name in names:
            raise ValueError(f"Duplicate skill manifest name at {path}:{line_number}: {name}")
        if provider == "local":
            source_path = Path(source)
            if source_path.is_absolute() or ".." in source_path.parts:
                raise ValueError(
                    f"Local skill source must stay inside the repository at "
                    f"{path}:{line_number}: {source}"
                )

        names.add(name)
        rows.append((provider, name, source, require_skill_file))

    if not rows:
        raise ValueError(f"Skill manifest is empty: {path}")
    return rows


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

        if operation == "manifest" and len(argv) == 3:
            for row in read_skill_manifest(argv[2]):
                print("\t".join(row))
            return 0
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"usage: agent_stack.py {operation} ...", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv))
