"""Select reviewed local Pi resources; never install or modify upstream sources."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

DIRECTORY = Path(__file__).resolve().parent


def pinned_source(agent_dir, name):
    file = "subagent-source.json" if name == "subagent-manager" else "sources.json"
    manifest = json.loads((DIRECTORY/file).read_text())[name]
    root = agent_dir/"port-resources/git/github.com"/manifest["repository"]
    if not root.is_dir():
        raise ValueError(f"Install the pinned {name} source in the selected Pi agent directory first")
    for relative, expected in manifest["files"].items():
        file = root/relative
        if (file.is_symlink() or not file.is_file() or not file.resolve().is_relative_to(root.resolve())
                or hashlib.sha256(file.read_bytes()).hexdigest() != expected):
            raise ValueError(f"The installed {name} source differs from the reviewed pin")
    return root, manifest


def patched_logger(agent_dir, stage):
    source, manifest = pinned_source(agent_dir, "learn")
    target = stage/"extensions/md-log.ts"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source/"extensions/md-log.ts", target)
    env = {"HOME": str(stage), "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
           "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"}
    patch = DIRECTORY/"patches/learn-md-log.patch"
    for flags in (["--check"], []):
        try:
            subprocess.run(["git", "apply", "--no-index", *flags, str(patch)], cwd=stage, env=env,
                           capture_output=True, check=True, timeout=10)
        except (OSError, subprocess.SubprocessError):
            raise ValueError("The reviewed Learn logger patch could not be applied") from None
    if hashlib.sha256(target.read_bytes()).hexdigest() != manifest["patched_logger_sha256"]:
        raise ValueError("The staged Learn logger differs from the verified patch")
    return target


def stage_subagents(agent_dir, stage):
    manager, manifest = pinned_source(agent_dir, "subagent-manager")
    learn, learn_manifest = pinned_source(agent_dir, "learn")
    ysk, ysk_manifest = pinned_source(agent_dir, "you-should-know")
    for source, folder, files in ((manager, "manager", manifest["files"]),
                                  (learn, "learn", learn_manifest["files"]),
                                  (ysk/"extensions/you-should-know", "ysk", ("index.ts", "detect-prompt.md"))):
        for relative in files:
            target = stage/folder/relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source/relative, target)
    shutil.copyfile(DIRECTORY/"child-extensions.ts", stage/"manager/port-child.ts")
    shutil.copyfile(DIRECTORY/"AGENTS.md", stage/"manager/port-instructions.md")
    env = {"HOME": str(stage), "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
           "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"}
    for name in ("subagent-child-runtime", "learn-child-visuals", "ysk-sdk-child"):
        for flags in (["--check"], []):
            try:
                subprocess.run(["git", "apply", "--no-index", *flags, str(DIRECTORY/"patches"/(name+".patch"))],
                               cwd=stage, env=env, capture_output=True, check=True, timeout=10)
            except (OSError, subprocess.SubprocessError):
                raise ValueError("An approved child-integration patch could not be applied") from None
    dependencies = manager/"node_modules"
    renderer = agent_dir/"port-resources/renderer/node_modules"
    if not dependencies.is_dir() or not (renderer/".bin/mmdc").is_file():
        raise ValueError("Install the approved private manager and renderer dependencies first")
    renderer_root = renderer.parent
    for name in ("package.json", "package-lock.json"):
        if (renderer_root/name).read_bytes() != (DIRECTORY/"renderer"/name).read_bytes():
            raise ValueError("The private renderer manifest differs from the reviewed runtime dependencies")
    if json.loads((renderer/"@mermaid-js/mermaid-cli/package.json").read_text()).get("version") != "11.16.0":
        raise ValueError("The installed Mermaid CLI differs from the reviewed version")
    (stage/"manager/node_modules").symlink_to(dependencies.resolve(), target_is_directory=True)
    (stage/"learn/extensions/visual-tools/node_modules").symlink_to(renderer.resolve(), target_is_directory=True)
    return stage


def selected_resources(agent_dir, stage, with_ysk=False, with_subagents=False):
    learn, _ = pinned_source(agent_dir, "learn")
    logger = patched_logger(agent_dir, stage)
    extensions = [learn/"extensions/ask-user-question.ts", learn/"extensions/quiz.ts", logger,
                  learn/"extensions/visual-tools/index.ts"]
    integration = stage_subagents(agent_dir, stage/"integration") if with_subagents else None
    if integration:
        extensions.append(integration/"manager/src/index.ts")
    if with_ysk:
        ysk, _ = pinned_source(agent_dir, "you-should-know")
        observer = integration/"ysk" if integration else stage/"ysk"
        if not integration:
            observer.mkdir(parents=True, exist_ok=True)
            for name in ("index.ts", "detect-prompt.md"):
                shutil.copyfile(ysk/"extensions/you-should-know"/name, observer/name)
            env = {"HOME": str(stage), "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                   "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"}
            for flags in (["--check"], []):
                try:
                    subprocess.run(["git", "apply", "--no-index", *flags, str(DIRECTORY/"patches/ysk-sdk-child.patch")],
                                   cwd=stage, env=env, capture_output=True, check=True, timeout=10)
                except (OSError, subprocess.SubprocessError):
                    raise ValueError("The approved observer patch could not be applied") from None
        # The selected observer effort is independent of the main model family.
        main = observer/"main.ts"
        main.write_text('import observe from "./index.ts"; export default function(pi:any) { '
                        'observe(pi, {observerModel:process.env.YSK_MODEL?.trim(), observerThinking:"max"}); }\n')
        extensions.append(main)
    skills = []
    for line in (DIRECTORY/"skills.tsv").read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        name, _, _ = line.split("\t")
        selected_learn = integration/"learn" if integration else learn
        external = json.loads((DIRECTORY/"catalog.json").read_text()).get("external", {})
        if name in external:
            spec = external[name]
            file = agent_dir/"port-resources/git/github.com"/spec["repository"]/spec["path"]/"SKILL.md"
            for relative, expected in spec["files"].items():
                source = file.parent/relative
                if source.is_symlink() or not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest() != expected:
                    raise ValueError("An approved external skill differs from its reviewed pin")
        else:
            file = (selected_learn/"skills"/name/"SKILL.md" if name in ("teach", "visualize")
                    else DIRECTORY/"catalog/skills"/name/"SKILL.md")
        if not file.is_file():
            raise ValueError("An approved skill file is missing")
        skills.append(file)
    return extensions, skills
