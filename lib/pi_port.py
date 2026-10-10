#!/usr/bin/env python3
"""Private installation utilities. Never access authentication or dotenv files."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.request

REPO = Path(__file__).resolve().parent.parent
MARKER = "guisaliba/agents pi-port v1\n"


def prepare(root):
    if (root/".managed").is_symlink():
        raise ValueError("The installation ownership marker is a symlink")
    if root.is_symlink() or (root.exists() and not (root/".managed").is_file()):
        raise ValueError("The installation root exists without a Pi port ownership marker")
    if root.exists() and (root/".managed").read_text() != MARKER:
        raise ValueError("The installation root belongs to another setup")
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    root.chmod(0o700)
    (root/".managed").write_text(MARKER)
    for folder in ("runtime", "packages", "agent"):
        if (root/folder).is_symlink():
            raise ValueError("A private installation directory is a symlink")
        (root/folder).mkdir(exist_ok=True, mode=0o700)


def manifests(source, target):
    if target.is_symlink():
        raise ValueError("A dependency directory is a symlink")
    target.mkdir(parents=True, exist_ok=True)
    for name in ("package.json", "package-lock.json"):
        file = target/name
        body = (source/name).read_bytes()
        if file.is_symlink() or (file.exists() and file.read_bytes() != body):
            raise ValueError("A private dependency manifest conflicts with the reviewed lock: "+str(file))
        file.write_bytes(body)


def extract(archive, target, kind):
    raw = target.with_name(target.name+"-unpack")
    raw.mkdir()
    with tarfile.open(archive) as stream:
        for member in stream.getmembers():
            name = Path(member.name)
            destination = (raw/name).resolve()
            if name.is_absolute() or not destination.is_relative_to(raw.resolve()):
                raise ValueError("Unsafe release archive path")
            if member.isdev() or member.isfifo():
                raise ValueError("Unsafe release archive member")
            if member.issym() or member.islnk():
                link = Path(member.linkname)
                base = destination.parent if member.issym() else raw
                if link.is_absolute() or not (base/link).resolve().is_relative_to(raw.resolve()):
                    raise ValueError("Unsafe release archive link")
        # Explicit safety checks above support Python 3.9+ as well as newer tar filters.
        stream.extractall(raw, filter="data") if sys.version_info >= (3, 12) else stream.extractall(raw)
    if kind == "node":
        candidates = [p.parent.parent for p in raw.glob("*/bin/node")]
        if len(candidates) != 1:
            raise ValueError("Node archive layout differs from the locked release")
        candidates[0].rename(target)
        shutil.rmtree(raw)
    else:
        matches = [p for p in raw.rglob(kind) if p.is_file() and not p.is_symlink()]
        if len(matches) != 1:
            raise ValueError("Native archive does not have one expected executable")
        target.mkdir()
        shutil.copyfile(matches[0], target/kind)
        (target/kind).chmod(0o755)
        shutil.rmtree(raw)


def versions(root):
    for name, file, expected in (("node", "bin/node", "v24.21.0"),
                                 ("ai-memory", "ai-memory", "ai-memory 2.6.2"),
                                 ("rtk", "rtk", "rtk 0.48.0")):
        result = subprocess.run([str(root/"runtime"/name/file), "--version"], check=True, capture_output=True, text=True)
        if result.stdout.strip() != expected:
            raise ValueError("Installed executable differs from its reviewed version: "+name)


def sources(root):
    sys.path.insert(0, str(REPO/"pi"))
    from resources import pinned_source
    agent = root/"agent"
    for manifest_file in ("sources.json", "subagent-source.json"):
        for name, spec in json.loads((REPO/"pi"/manifest_file).read_text()).items():
            destination = agent/"port-resources/git/github.com"/spec["repository"]
            if not destination.exists():
                destination.parent.mkdir(parents=True, exist_ok=True)
                subprocess.run(["git", "clone", "--no-checkout", "https://github.com/"+spec["repository"]+".git", str(destination)], check=True)
                subprocess.run(["git", "-c", "core.hooksPath=/dev/null", "-C", str(destination), "checkout", "--detach", spec["commit"]], check=True)
            pinned_source(agent, name)
    manager = agent/"port-resources/git/github.com/championswimmer/pi-subagent-manager/node_modules"
    renderer = agent/"port-resources/renderer"
    for link, target in ((manager, root/"packages/manager/node_modules"), (renderer, root/"packages/renderer")):
        if link.is_symlink() and link.resolve() == target.resolve():
            continue
        if link.exists() or link.is_symlink():
            raise ValueError("A private resource dependency path conflicts")
        link.symlink_to(target.resolve(), target_is_directory=True)
    catalog = json.loads((REPO/"pi/catalog.json").read_text())
    for spec in catalog.get("external", {}).values():
        destination = agent/"port-resources/git/github.com"/spec["repository"]
        if not destination.exists():
            destination.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["git", "clone", "--no-checkout", "https://github.com/"+spec["repository"]+".git", str(destination)], check=True)
            subprocess.run(["git", "-c", "core.hooksPath=/dev/null", "-C", str(destination), "checkout", "--detach", spec["commit"]], check=True)
        for relative, expected in spec["files"].items():
            file = destination/spec["path"]/relative
            if file.is_symlink() or hashlib.sha256(file.read_bytes()).hexdigest() != expected:
                raise ValueError("The approved external skill differs: "+relative)
    for relative, expected in catalog["files"].items():
        file = REPO/"pi"/relative
        if file.is_symlink() or hashlib.sha256(file.read_bytes()).hexdigest() != expected:
            raise ValueError("The reviewed skill snapshot differs: "+relative)


def systemd_quote(value):
    return '"'+str(value).replace('\\', '\\\\').replace('"', '\\"').replace('%', '%%')+'"'


def configure(root):
    state_file = root/"managed-files.json"
    if state_file.is_symlink():
        raise ValueError("The managed-file record is a symlink")
    previous = json.loads(state_file.read_text()) if state_file.exists() else {}
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home()/".config")))
    files = {
        root/"memory.toml": 'embedding_provider = "none"\nlog_level = "error"\n[auto_improve]\nrequire_approval = true\n[auto_improve.scheduler]\nenabled = false\n[decay]\nobservation_retention_days = 0\n[auto_scope]\nmode = "per_actor"\n',
        root/"install.json": json.dumps({"repository": str(REPO), "endpoint": "http://127.0.0.1:49375"}, indent=2)+"\n",
        root/"agent/you-should-know/config.json": (REPO/"pi/ysk-config.json").read_text(),
    }
    import shlex
    files[Path.home()/".local/bin/pi-port"] = "#!/usr/bin/env bash\nset -Eeuo pipefail\nexport PI_PORT_HOME="+shlex.quote(str(root))+"\nexec "+shlex.quote(str(REPO/"bin/pi-port"))+" \"$@\"\n"
    files[root/"bin/memory-service"] = "#!/usr/bin/env bash\nset -Eeuo pipefail\nexport PI_PORT_HOME="+shlex.quote(str(root))+"\nexec "+shlex.quote(str(REPO/"bin/pi-port-memory"))+"\n"
    files[root/"bin/ai-memory"] = "#!/usr/bin/env bash\nset -Eeuo pipefail\nunset AI_MEMORY_AUTH_TOKEN AI_MEMORY_AUTH_TOKEN_FILE\nexport AI_MEMORY_SERVER_URL=http://127.0.0.1:49375\nexec "+shlex.quote(str(root/"runtime/ai-memory/ai-memory"))+" --data-dir "+shlex.quote(str(Path.home()/".local/share/ai-memory"))+" --config "+shlex.quote(str(root/"memory.toml"))+" \"$@\"\n"
    unit = config_home/"systemd/user/pi-port-memory.service"
    files[unit] = "\n".join(["# Managed by guisaliba/agents Pi port", "[Unit]", "Description=Pi port ai-memory (private runtime, existing store)", "[Service]", "Type=simple", "ExecStart="+systemd_quote(root/"bin/memory-service"), "Restart=on-failure", "RestartSec=3", "UMask=0077", "[Install]", "WantedBy=default.target", ""])
    # Validate every destination before any write. No credential paths are involved.
    for file, body in files.items():
        if file.is_symlink():
            raise ValueError("A managed destination is a symlink: "+str(file))
        if file.exists():
            digest = hashlib.sha256(file.read_bytes()).hexdigest()
            wanted = hashlib.sha256(body.encode()).hexdigest()
            if digest != wanted and previous.get(str(file)) != digest:
                raise ValueError("A managed destination has unrelated or edited content: "+str(file))
    record = {}
    for file, body in files.items():
        file.parent.mkdir(parents=True, exist_ok=True)
        temporary = file.with_name(file.name+".pi-port-new")
        with temporary.open("x") as stream:
            stream.write(body)
        temporary.chmod(0o700 if file.name in ("pi-port", "memory-service", "ai-memory") else 0o600)
        temporary.replace(file)
        record[str(file)] = hashlib.sha256(body.encode()).hexdigest()
    state_file.write_text(json.dumps(record, indent=2)+"\n")


def health(root):
    sys.path.insert(0, str(REPO/"pi"))
    from launch import check_server, LaunchError
    endpoint = json.loads((root/"install.json").read_text())["endpoint"]
    for _ in range(30):
        try:
            check_server(endpoint)
            print("PASS: permanent memory service serves the approved store")
            return
        except LaunchError:
            time.sleep(0.5)
    raise ValueError("Memory service did not become healthy. Another server may own the store lock; never use --force.")


def main():
    command, *args = sys.argv[1:]
    if command == "asset":
        name, arch = args
        spec = json.loads((REPO/"pi/releases.json").read_text())[name][arch]
        print(spec["url"]); print(spec["sha256"]); print(spec["archive"])
    elif command == "extract":
        extract(Path(args[0]), Path(args[1]), args[2])
    elif command == "manifests":
        manifests(Path(args[0]), Path(args[1]))
    else:
        {"prepare": prepare, "versions": versions, "sources": sources,
         "configure": configure, "health": health}[command](Path(args[0]))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.SubprocessError) as error:
        print("Pi installation failed: "+(str(error) if isinstance(error, ValueError) else type(error).__name__), file=sys.stderr)
        sys.exit(1)
