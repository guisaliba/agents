#!/usr/bin/env python3
"""Launch only the approved Pi resources. Does not install or start services.

Select a separately authenticated agent directory and an existing local
ai-memory 2.6.2 server. Resource generators run with a private HOME/config.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request

from resources import selected_resources

PRIMARY_MODELS = ("openai/gpt-6.1-sol", "openai/gpt-6-luna")
VERIFICATION_MODEL = "opencode-go/deepseek-v4.1-flash"


class LaunchError(Exception):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def local_endpoint(value):
    try:
        url = urllib.parse.urlsplit(value)
        if (url.scheme != "http" or url.hostname != "127.0.0.1" or not url.port
                or url.username is not None or url.password is not None
                or url.path not in ("", "/") or url.query or url.fragment):
            raise ValueError()
    except ValueError:
        raise argparse.ArgumentTypeError("Use http://127.0.0.1:PORT with no credentials or extra path")
    return value.rstrip("/")


def executable(value):
    found = shutil.which(str(value))
    if not found:
        raise LaunchError("A required executable is unavailable")
    return str(Path(found).resolve())


def generate(command, cwd, env):
    try:
        result = subprocess.run(command, cwd=cwd, env=env, capture_output=True,
                                text=True, timeout=20, check=True)
    except (OSError, subprocess.SubprocessError):
        # Do not print generator diagnostics or inherited credential values.
        raise LaunchError("An upstream resource generator failed") from None
    return result.stdout


def check_server(endpoint):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        with opener.open(endpoint+"/admin/status", timeout=5) as response:
            status = json.loads(response.read(65537))
        expected = (Path.home()/".local/share/ai-memory/db/memory.sqlite").resolve()
        if status.get("version") != "2.6.2" or Path(status.get("db_path", "")).resolve() != expected:
            raise ValueError()
    except (OSError, ValueError, TypeError, AttributeError):
        raise LaunchError("ai-memory is unavailable or does not serve the approved 2.6.2 store") from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent-dir", type=Path, required=True,
                        help="Existing Pi directory; authenticate with Pi /login, never copy auth files")
    parser.add_argument("--memory-binary", required=True, help="Approved ai-memory 2.6.2 executable")
    parser.add_argument("--memory-endpoint", type=local_endpoint, required=True)
    parser.add_argument("--pi-binary", default="pi", help="Pi 1.1.0 executable")
    models = parser.add_mutually_exclusive_group(required=True)
    models.add_argument("--model", choices=PRIMARY_MODELS, help="Explicit primary model; no role implementation")
    models.add_argument("--verification-model", choices=(VERIFICATION_MODEL,), help="Approved isolated testing only")
    parser.add_argument("--subagents", action="store_true", help="Load the approved subagent manager")
    parser.add_argument("--ysk-model", choices=PRIMARY_MODELS,
                        help="Load YSK with an explicit approved observer model")
    parser.add_argument("--mode", choices=("text", "json", "rpc"), default="text")
    parser.add_argument("--print", dest="print_mode", action="store_true")
    parser.add_argument("--no-session", action="store_true", help="Use an in-memory Pi session")
    parser.add_argument("--continue", dest="continue_session", action="store_true")
    parser.add_argument("--resume", action="store_true", help="Open Pi's session picker; select the managed main session")
    parser.add_argument("messages", nargs="*")
    args = parser.parse_args()
    agent_dir = args.agent_dir.expanduser().resolve()
    if not agent_dir.is_dir():
        parser.error("Create and authenticate the chosen Pi agent directory first")
    if any((agent_dir/name).exists() for name in ("SYSTEM.md", "APPEND_SYSTEM.md", "models.json")):
        parser.error("The chosen agent directory contains unapproved system-prompt or model overrides")
    if args.verification_model and agent_dir == (Path.home()/".pi/agent").resolve():
        parser.error("Verification must not use the shared Pi agent directory")
    if args.mode == "rpc" and (args.messages or args.print_mode):
        parser.error("RPC mode takes prompts through stdin, not positional messages or --print")
    if sum((args.continue_session, args.resume, args.no_session)) > 1:
        parser.error("Select only one of --continue, --resume, or --no-session")
    if args.resume and (args.mode == "rpc" or args.print_mode):
        parser.error("The resume picker requires an interactive session")
    if args.verification_model and (args.continue_session or args.resume):
        parser.error("Verification must not resume existing sessions")
    model = args.model or args.verification_model
    instructions = Path(__file__).resolve().with_name("AGENTS.md")
    try:
        if not instructions.is_file():
            raise LaunchError("The approved Pi instruction file is missing")
        pi_binary, memory_binary, rtk_binary = map(executable, (args.pi_binary, args.memory_binary, "rtk"))
        check_server(args.memory_endpoint)
        with tempfile.TemporaryDirectory(prefix="agents-pi-launch-") as temporary:
            root = Path(temporary)
            root.chmod(0o700)
            home = root/"home"
            home.mkdir()
            generator_env = {"HOME": str(home), "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                             "LANG": "C.UTF-8", "XDG_CONFIG_HOME": str(root/"config"),
                             "XDG_DATA_HOME": str(root/"data")}
            for binary, expected in ((pi_binary, "1.1.0"), (memory_binary, "ai-memory 2.6.2"),
                                     (rtk_binary, "rtk 0.48.0")):
                if generate([binary, "--version"], root, generator_env).strip() != expected:
                    raise LaunchError("Executable version differs from the verified port versions")
            config = root/"generator.toml"
            config.write_text('embedding_provider = "none"\n')
            payload = generate([memory_binary, "--data-dir", str(root/"generator"), "--config", str(config),
                                "install-hooks", "--agent", "pi", "--server-url", args.memory_endpoint,
                                "--capture-mode", "denylist", "--project-strategy", "repo-root"], root, generator_env)
            if 'const TOKEN: string | null = null;' not in payload or '"denylist" = "denylist";' not in payload:
                raise LaunchError("Unexpected upstream memory authentication or capture configuration")
            memory_extension = root/"ai-memory.ts"
            memory_extension.write_text(payload)
            generate([rtk_binary, "init", "--agent", "pi", "--no-trust-filters"], root, generator_env)
            rtk_extension = root/".pi/extensions/rtk.ts"
            if not rtk_extension.is_file():
                raise LaunchError("The upstream RTK extension was not generated")
            try:
                selection = {"with_ysk": bool(args.ysk_model)}
                if args.subagents:
                    selection["with_subagents"] = True
                extensions, skills = selected_resources(agent_dir, root/"learn", **selection)
            except ValueError as error:
                raise LaunchError(str(error)) from None
            scoped = [model] if args.verification_model else list(PRIMARY_MODELS)
            if args.subagents:
                config = json.loads(Path(__file__).with_name("subagent-config.json").read_text())
                scoped = list(dict.fromkeys(scoped + [m for a in config["agents"].values() for m in a["models"]]))
            command = [pi_binary, "--offline", "--no-extensions", "--extension", str(memory_extension),
                       "--extension", str(rtk_extension), "--no-mcp", "--no-skills", "--no-context-files",
                       "--no-prompt-templates", "--no-themes", "--no-approve",
                       "--append-system-prompt", str(instructions), "--model", model,
                       "--models", ",".join(scoped),
                       "--tools", "read,bash,edit,write,memory_*,ask_user_question,quiz" + (",agent_*" if args.subagents else ""), "--mode", args.mode,
                       "--session-dir", str(agent_dir/"sessions")]
            for extension in extensions:
                command += ["--extension", str(extension)]
            for skill in skills:
                command += ["--skill", str(skill)]
            if args.print_mode:
                command.append("--print")
            if args.no_session:
                command.append("--no-session")
            if args.continue_session:
                command.append("--continue")
            if args.resume:
                command.append("--resume")
            command += ["--", *args.messages]
            environment = {**os.environ, "PI_CODING_AGENT_DIR": str(agent_dir),
                           "AI_MEMORY_DATA_DIR": str(Path.home()/".local/share/ai-memory")}
            # Child observation follows explicit launcher selection, not inherited overrides.
            environment.pop("PI_PORT_CHILD_YSK_MODEL", None)
            if args.ysk_model:
                environment["YSK_MODEL"] = args.ysk_model
                if args.subagents:
                    environment["PI_PORT_CHILD_YSK_MODEL"] = args.ysk_model
            if environment.get("AI_MEMORY_CAPTURE_OWNER", "").strip():
                raise LaunchError("An external capture owner would disable Pi capture; start outside that wrapper")
            # Do not inherit a different harness's managed lifecycle identity.
            environment.pop("AI_MEMORY_RUN_ID", None)
            child = subprocess.Popen(command, env=environment)
            previous_int = signal.signal(signal.SIGINT, signal.SIG_IGN)
            previous_term = signal.signal(signal.SIGTERM, lambda signum, frame: child.send_signal(signum))
            try:
                code = child.wait()
            finally:
                signal.signal(signal.SIGINT, previous_int)
                signal.signal(signal.SIGTERM, previous_term)
            return code if code >= 0 else 128-code
    except (LaunchError, OSError) as error:
        print(f"Pi launch failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
