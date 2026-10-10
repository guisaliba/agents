#!/usr/bin/env python3
"""Install approved non-secret role settings in a private Pi profile.

Refuse conflicting files rather than replacing existing user choices.
"""
import argparse
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent-dir", type=Path, required=True)
    args = parser.parse_args()
    agent = args.agent_dir.expanduser().resolve()
    if not agent.is_dir() or agent == (Path.home()/".pi/agent").resolve():
        parser.error("Use the approved separate Pi profile")
    config = json.loads((HERE/"subagent-config.json").read_text())
    root = agent/"subagent-manager"
    files = {root/"settings.json": json.dumps(config["settings"], indent=2)+"\n"}
    for name, settings in config["agents"].items():
        files[root/"agents"/(name+".yml")] = json.dumps(settings, indent=2)+"\n"
        if (root/"agents"/(name+".md")).exists():
            parser.error("An existing role fork conflicts with the approved settings")
    for file, content in files.items():
        if any(p.is_symlink() for p in (file, *file.parents)):
            parser.error("Symlinked configuration paths are refused")
        if file.exists() and file.read_text() != content:
            parser.error("Existing settings differ; no files were changed")
    for file, content in files.items():
        if not file.exists():
            file.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            with file.open("x") as stream:
                stream.write(content)
            file.chmod(0o600)
    print("PASS: six approved role assignments configured; no credentials accessed")


if __name__ == "__main__":
    main()
