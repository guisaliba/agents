#!/usr/bin/env python3

import os
import runpy
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "journal-task-sync"
ENV = {**os.environ, "GIT_ALLOW_PROTOCOL": "file"}


def git(*args: str, cwd: Path | None = None) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=cwd,
        env=ENV,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.stdout.strip()


def configure_repo(path: Path) -> None:
    git("config", "user.name", "Daily Tasks Test", cwd=path)
    git("config", "user.email", "daily-tasks-test@example.invalid", cwd=path)


class JournalTaskSyncTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.journal_remote = self.root / "journal.git"
        self.brain_remote = self.root / "brain.git"
        self.workspace = self.root / "workspace"

        git("init", "--bare", "--initial-branch=main", str(self.journal_remote))
        journal_seed = self.root / "journal-seed"
        git("init", "--initial-branch=main", str(journal_seed))
        configure_repo(journal_seed)
        (journal_seed / "README.md").write_text("# Journal\n", encoding="utf-8")
        git("add", "README.md", cwd=journal_seed)
        git("commit", "-m", "chore: initialize journal", cwd=journal_seed)
        git("remote", "add", "origin", str(self.journal_remote), cwd=journal_seed)
        git("push", "-u", "origin", "main", cwd=journal_seed)

        git("init", "--bare", "--initial-branch=main", str(self.brain_remote))
        brain_seed = self.root / "brain-seed"
        git("init", "--initial-branch=main", str(brain_seed))
        configure_repo(brain_seed)
        (brain_seed / "README.md").write_text("# Brain\n", encoding="utf-8")
        git("add", "README.md", cwd=brain_seed)
        git("commit", "-m", "chore: initialize brain", cwd=brain_seed)
        git(
            "-c",
            "protocol.file.allow=always",
            "submodule",
            "add",
            "-b",
            "main",
            str(self.journal_remote),
            "journal",
            cwd=brain_seed,
        )
        git("commit", "-am", "chore: add journal", cwd=brain_seed)
        git("remote", "add", "origin", str(self.brain_remote), cwd=brain_seed)
        git("push", "-u", "origin", "main", cwd=brain_seed)

        git(
            "-c",
            "protocol.file.allow=always",
            "clone",
            "--recurse-submodules",
            str(self.brain_remote),
            str(self.workspace),
        )
        configure_repo(self.workspace)
        journal = self.workspace / "journal"
        configure_repo(journal)
        git("switch", "-C", "main", "--track", "origin/main", cwd=journal)

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def run_sync(self, operation: str, *, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), operation, str(self.workspace)],
            env=ENV,
            check=check,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    def write_task(self, text: str = "- [ ] Test the task flow\n") -> Path:
        task = self.workspace / "journal" / "tasks" / "2026-08-29.md"
        task.parent.mkdir(parents=True, exist_ok=True)
        task.write_text(text, encoding="utf-8")
        return task

    def test_git_environment_uses_user_ssh_config(self) -> None:
        home = self.root / "home"
        ssh_config = home / ".ssh" / "config"
        ssh_config.parent.mkdir(parents=True)
        ssh_config.write_text("Host github.com\n", encoding="utf-8")

        with patch.dict(os.environ, {"HOME": str(home)}):
            git_environment = runpy.run_path(str(SCRIPT))["git_environment"]
            environment = git_environment()

        self.assertEqual(environment["GIT_SSH_COMMAND"], f"ssh -F {ssh_config}")

    def test_publish_pushes_task_commit_and_parent_gitlink(self) -> None:
        self.write_task()

        self.run_sync("publish")

        journal_remote_head = git("rev-parse", "refs/heads/main", cwd=self.journal_remote)
        parent_gitlink = git("ls-tree", "refs/heads/main", "journal", cwd=self.brain_remote).split()[2]
        self.assertEqual(parent_gitlink, journal_remote_head)
        self.assertEqual(git("status", "--porcelain", cwd=self.workspace), "")
        self.assertEqual(git("status", "--porcelain", cwd=self.workspace / "journal"), "")

    def test_publish_with_no_change_is_idempotent(self) -> None:
        self.write_task()
        self.run_sync("publish")
        parent_head = git("rev-parse", "refs/heads/main", cwd=self.brain_remote)
        journal_head = git("rev-parse", "refs/heads/main", cwd=self.journal_remote)

        result = self.run_sync("publish")

        self.assertIn("nothing to publish", result.stdout)
        self.assertEqual(git("rev-parse", "refs/heads/main", cwd=self.brain_remote), parent_head)
        self.assertEqual(git("rev-parse", "refs/heads/main", cwd=self.journal_remote), journal_head)

    def test_publish_refuses_unrelated_journal_changes(self) -> None:
        entry = self.workspace / "journal" / "2026-08-29.md"
        entry.write_text("Private entry\n", encoding="utf-8")
        journal_head = git("rev-parse", "refs/heads/main", cwd=self.journal_remote)

        result = self.run_sync("publish", check=False)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside tasks/", result.stderr)
        self.assertTrue(entry.exists())
        self.assertEqual(git("rev-parse", "refs/heads/main", cwd=self.journal_remote), journal_head)

    def test_publish_stops_when_remote_moves_over_local_task_change(self) -> None:
        task = self.write_task("- [ ] Local version\n")
        writer = self.root / "writer"
        git("clone", str(self.journal_remote), str(writer))
        configure_repo(writer)
        remote_task = writer / "tasks" / "2026-08-29.md"
        remote_task.parent.mkdir(parents=True, exist_ok=True)
        remote_task.write_text("- [ ] Remote version\n", encoding="utf-8")
        git("add", "tasks/2026-08-29.md", cwd=writer)
        git("commit", "-m", "chore(tasks): remote update", cwd=writer)
        git("push", "origin", "main", cwd=writer)

        result = self.run_sync("publish", check=False)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("remote journal changed", result.stderr)
        self.assertEqual(task.read_text(encoding="utf-8"), "- [ ] Local version\n")

    def test_pull_fast_forwards_parent_and_journal(self) -> None:
        writer = self.root / "writer"
        git(
            "-c",
            "protocol.file.allow=always",
            "clone",
            "--recurse-submodules",
            str(self.brain_remote),
            str(writer),
        )
        configure_repo(writer)
        writer_journal = writer / "journal"
        configure_repo(writer_journal)
        git("switch", "-C", "main", "--track", "origin/main", cwd=writer_journal)
        task = writer_journal / "tasks" / "2026-08-29.md"
        task.parent.mkdir(parents=True, exist_ok=True)
        task.write_text("- [ ] Remote task\n", encoding="utf-8")
        git("add", "tasks/2026-08-29.md", cwd=writer_journal)
        git("commit", "-m", "chore(tasks): add remote task", cwd=writer_journal)
        git("push", "origin", "main", cwd=writer_journal)
        git("add", "journal", cwd=writer)
        git("commit", "-m", "chore(journal): update submodule", cwd=writer)
        git("push", "origin", "main", cwd=writer)

        self.run_sync("pull")

        pulled = self.workspace / "journal" / "tasks" / "2026-08-29.md"
        self.assertEqual(pulled.read_text(encoding="utf-8"), "- [ ] Remote task\n")
        self.assertEqual(git("status", "--porcelain", cwd=self.workspace), "")
        self.assertEqual(git("status", "--porcelain", cwd=self.workspace / "journal"), "")


if __name__ == "__main__":
    unittest.main()
