#!/usr/bin/env python3
"""Focused launcher checks; real product-path evidence is in verify-launch.py."""
import argparse
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch, Mock

spec = importlib.util.spec_from_file_location("launcher", Path(__file__).with_name("launch.py"))
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)


class LauncherTests(unittest.TestCase):
    def test_loopback_endpoint(self):
        self.assertEqual(launcher.local_endpoint("http://127.0.0.1:36925/"), "http://127.0.0.1:36925")

    def test_other_endpoints_are_rejected(self):
        for url in ("https://127.0.0.1:1234", "http://localhost:1234", "http://127.0.0.1",
                    "http://fixture@127.0.0.1:1234", "http://127.0.0.1:1234/path",
                    "http://127.0.0.1:1234?query", "http://127.0.0.1:1234#fragment", "http://127.0.0.1:99999"):
            with self.subTest(url=url), self.assertRaises(argparse.ArgumentTypeError):
                launcher.local_endpoint(url)

    def test_redirect_is_not_followed(self):
        self.assertIsNone(launcher.NoRedirect().redirect_request(None, None, 302, "", {}, "http://example.invalid"))

    def test_backend_must_match_version_and_selected_store(self):
        expected = str(Path.home()/".local/share/ai-memory/db/memory.sqlite")
        for status in ({"version": "2.6.2", "db_path": expected},
                       {"version": "2.6.0", "db_path": expected},
                       {"version": "2.6.2", "db_path": "/wrong-store.sqlite"}, {}, []):
            with self.subTest(status=status):
                response = Mock()
                response.read.return_value = json.dumps(status).encode()
                response.__enter__ = Mock(return_value=response)
                response.__exit__ = Mock(return_value=False)
                with patch.object(launcher.urllib.request, "build_opener") as opener:
                    opener.return_value.open.return_value = response
                    if isinstance(status, dict) and status.get("version") == "2.6.2" and status.get("db_path") == expected:
                        launcher.check_server("http://127.0.0.1:1234")
                    else:
                        with self.assertRaises(launcher.LaunchError):
                            launcher.check_server("http://127.0.0.1:1234")

    def test_unavailable_backend_is_a_clear_failure(self):
        with patch.object(launcher.urllib.request, "build_opener") as opener:
            opener.return_value.open.side_effect = OSError("unavailable")
            with self.assertRaisesRegex(launcher.LaunchError, "unavailable"):
                launcher.check_server("http://127.0.0.1:1234")

    def test_generator_diagnostics_are_not_disclosed(self):
        with patch.object(launcher.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "fixture", stderr="SYNTHETIC_DIAGNOSTIC")):
            with self.assertRaisesRegex(launcher.LaunchError, "generator failed") as error:
                launcher.generate(["fixture"], Path("/tmp"), {})
            self.assertNotIn("SYNTHETIC_DIAGNOSTIC", str(error.exception))

    def arguments(self, agent, *extra):
        return ["launch.py", "--agent-dir", str(agent), "--memory-binary", "ai-memory",
                "--memory-endpoint", "http://127.0.0.1:1234", *extra]

    def rejected(self, args):
        with patch.object(sys, "argv", args), contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
            launcher.main()
        self.assertEqual(error.exception.code, 2)

    def test_primary_model_requires_explicit_selection(self):
        with tempfile.TemporaryDirectory() as agent:
            self.rejected(self.arguments(agent))
            self.rejected(self.arguments(agent, "--model", launcher.VERIFICATION_MODEL))

    def test_resource_overrides_are_not_accepted(self):
        with tempfile.TemporaryDirectory() as agent:
            self.rejected(self.arguments(agent, "--model", launcher.PRIMARY_MODELS[0], "--extension", "unapproved.ts"))

    def test_unapproved_global_prompt_or_model_overrides_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            agent = Path(directory)
            for name in ("SYSTEM.md", "APPEND_SYSTEM.md", "models.json"):
                file = agent/name
                file.write_text("synthetic fixture")
                self.rejected(self.arguments(agent, "--model", launcher.PRIMARY_MODELS[0]))
                file.unlink()

    def test_incompatible_session_options_are_rejected(self):
        with tempfile.TemporaryDirectory() as agent:
            for extra in (("--mode", "rpc", "prompt"), ("--mode", "rpc", "--print"),
                          ("--continue", "--no-session"), ("--resume", "--no-session"),
                          ("--resume", "--continue"), ("--resume", "--mode", "rpc"),
                          ("--resume", "--print")):
                self.rejected(self.arguments(agent, "--model", launcher.PRIMARY_MODELS[0], *extra))

    def test_verification_cannot_use_shared_agent_or_resume(self):
        with tempfile.TemporaryDirectory() as agent:
            self.rejected(self.arguments(agent, "--verification-model", launcher.VERIFICATION_MODEL, "--continue"))
        if (Path.home()/".pi/agent").is_dir():
            self.rejected(self.arguments(Path.home()/".pi/agent", "--verification-model", launcher.VERIFICATION_MODEL))

    def test_subagent_scope_and_child_observer_require_explicit_selection(self):
        with tempfile.TemporaryDirectory() as directory:
            agent = Path(directory)
            def generator(command, cwd, env):
                if "--version" in command:
                    return {"pi": "1.1.0", "ai-memory": "ai-memory 2.6.2", "rtk": "rtk 0.48.0"}[command[0]]
                if command[0] == "rtk":
                    file = cwd/".pi/extensions/rtk.ts"
                    file.parent.mkdir(parents=True)
                    file.write_text("synthetic RTK fixture")
                    return ""
                return 'const TOKEN: string | null = null;\nconst CAPTURE_MODE: "allowlist" | "denylist" = "denylist";'
            for subagents, observer, resume in ((False, False, False), (True, False, False),
                                                (True, True, False), (True, True, True)):
                extra = (["--subagents"] if subagents else []) + (["--ysk-model", "openai/gpt-6-luna"] if observer else [])
                extra += ["--resume"] if resume else []
                args = self.arguments(agent, "--model", launcher.PRIMARY_MODELS[0], *extra)
                with self.subTest(subagents=subagents, observer=observer), patch.object(sys, "argv", args), \
                        patch.object(launcher, "executable", side_effect=str), patch.object(launcher, "check_server"), \
                        patch.object(launcher, "generate", side_effect=generator), \
                        patch.object(launcher, "selected_resources", return_value=([], [])), \
                        patch.object(launcher.subprocess, "Popen") as popen, \
                        patch.dict(os.environ, {"PATH": "/usr/bin:/bin", "PI_PORT_CHILD_YSK_MODEL": "unapproved/model"}, clear=True):
                    popen.return_value.wait.return_value = 0
                    self.assertEqual(launcher.main(), 0)
                    command = popen.call_args.args[0]
                    env = popen.call_args.kwargs["env"]
                    self.assertEqual(env.get("PI_PORT_CHILD_YSK_MODEL"), "openai/gpt-6-luna" if observer else None)
                    self.assertEqual("agent_*" in command[command.index("--tools")+1], subagents)
                    self.assertEqual("--resume" in command, resume)
                    if subagents:
                        scoped = set(command[command.index("--models")+1].split(","))
                        self.assertTrue({"openai/gpt-6.1-sol", "openai/gpt-6-luna", "opencode-go/deepseek-v4.1-flash",
                                         "opencode-go/claude-haiku-5-5", "opencode-go/mimo-v2.6-pro"} <= scoped)

    def test_child_exit_code_and_selected_resources_are_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            agent = Path(directory)
            commands = []

            def generator(command, cwd, env):
                commands.append((command, dict(env)))
                if "--version" in command:
                    return {"pi": "1.1.0", "ai-memory": "ai-memory 2.6.2", "rtk": "rtk 0.48.0"}[command[0]]
                if command[0] == "rtk":
                    file = cwd/".pi/extensions/rtk.ts"
                    file.parent.mkdir(parents=True)
                    file.write_text("synthetic RTK fixture")
                    return ""
                return 'const TOKEN: string | null = null;\nconst CAPTURE_MODE: "allowlist" | "denylist" = "denylist";'

            def selected_resources(agent_dir, stage, with_ysk=False):
                stage.mkdir(parents=True)
                extensions = [stage/f"learn-{i}.ts" for i in range(4+int(with_ysk))]
                skills = [stage/f"skill-{i}.md" for i in range(20)]
                for file in extensions+skills:
                    file.write_text("synthetic external resource fixture")
                return extensions, skills

            args = self.arguments(agent, "--model", launcher.PRIMARY_MODELS[1])
            with patch.object(sys, "argv", args), patch.object(launcher, "executable", side_effect=str), \
                    patch.object(launcher, "check_server"), patch.object(launcher, "generate", side_effect=generator), \
                    patch.object(launcher, "selected_resources", side_effect=selected_resources), \
                    patch.object(launcher.subprocess, "Popen") as popen, \
                    patch.dict(os.environ, {"PATH": "/usr/bin:/bin", "AI_MEMORY_RUN_ID": "synthetic-parent"}, clear=True):
                popen.return_value.wait.return_value = 42
                self.assertEqual(launcher.main(), 42)
                command = popen.call_args.args[0]
                env = popen.call_args.kwargs["env"]
                self.assertNotIn("AI_MEMORY_RUN_ID", env)
                self.assertEqual(env["PI_CODING_AGENT_DIR"], str(agent))
                self.assertEqual(command[command.index("--model")+1], launcher.PRIMARY_MODELS[1])
                self.assertEqual(command.count("--extension"), 6)
                self.assertEqual(command.count("--skill"), 20)
                self.assertIn("ask_user_question,quiz", command[command.index("--tools")+1])
                self.assertEqual(command[command.index("--append-system-prompt")+1], str(Path(__file__).resolve().with_name("AGENTS.md")))
                memory_command = next(c for c, _ in commands if "install-hooks" in c)
                self.assertEqual(memory_command[memory_command.index("--capture-mode")+1], "denylist")
                self.assertNotIn("--apply", memory_command)
                self.assertTrue(all(Path(e["HOME"]) != Path.home() for _, e in commands))
                for i, flag in enumerate(command):
                    if flag == "--extension":
                        self.assertFalse(Path(command[i+1]).exists())


if __name__ == "__main__":
    unittest.main()
