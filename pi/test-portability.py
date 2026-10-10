#!/usr/bin/env python3
"""Check the portable installation contract without credentials or network."""
from pathlib import Path
import hashlib
import importlib.util
import json
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("installer", ROOT/"lib/pi_port.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class PortabilityTests(unittest.TestCase):
    def test_install_help_has_no_side_effects(self):
        script = ROOT/"install.sh"
        self.assertTrue(script.is_file(), "The approved Bash installation entry point is missing")
        result = subprocess.run(["bash", str(script), "--help"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--system-packages", result.stdout)

    def test_arch_derivative_is_supported(self):
        helper = ROOT/"lib/platform.sh"
        result = subprocess.run(["bash", "-c", 'source "$1"; pi_port_platform omarchy arch', "test", str(helper)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "arch")

    def test_supported_platforms_and_unknown_family(self):
        for identifier, like, expected in (("arch", "", "arch"), ("debian", "", "debian"),
                                           ("ubuntu", "debian", "ubuntu"), ("fedora", "", None)):
            with self.subTest(identifier=identifier):
                result = subprocess.run(["bash", "-c", 'source "$1"; pi_port_platform "$2" "$3"',
                                         "test", str(ROOT/"lib/platform.sh"), identifier, like], capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, expected is not None)
                if expected:
                    self.assertEqual(result.stdout.strip(), expected)

    def test_foreign_installation_root_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)/"foreign"
            root.mkdir()
            (root/"fixture").write_text("untouched")
            with self.assertRaises(ValueError):
                installer.prepare(root)
            self.assertEqual(list(root.iterdir()), [root/"fixture"])

    def test_private_root_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)/"private space"
            installer.prepare(root)
            installer.prepare(root)
            self.assertEqual(root.stat().st_mode & 0o777, 0o700)
            self.assertEqual((root/".managed").read_text(), installer.MARKER)

    def test_manifest_conflict_does_not_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory)
            (destination/"package.json").write_text("foreign")
            with self.assertRaises(ValueError):
                installer.manifests(ROOT/"pi/runtime", destination)
            self.assertEqual((destination/"package.json").read_text(), "foreign")
            self.assertFalse((destination/"package-lock.json").exists())

    def test_archive_traversal_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root/"bad.tar.gz"
            with tarfile.open(archive, "w:gz") as stream:
                stream.addfile(tarfile.TarInfo("../outside"))
            with self.assertRaises(ValueError):
                installer.extract(archive, root/"output", "ai-memory")
            self.assertFalse((root/"outside").exists())

    def test_catalog_has_exactly_twenty_skills_with_support_files(self):
        catalog = json.loads((ROOT/"pi/catalog.json").read_text())
        selected = {line.split("\t")[0] for line in (ROOT/"pi/skills.tsv").read_text().splitlines()
                    if line and not line.startswith("#")}
        self.assertEqual(len(selected), 20)
        self.assertEqual(set(catalog["skills"]) | {"teach", "visualize"}, selected)
        for relative, expected in catalog["files"].items():
            file = ROOT/"pi"/relative
            self.assertFalse(file.is_symlink())
            self.assertEqual(hashlib.sha256(file.read_bytes()).hexdigest(), expected, relative)
        self.assertTrue((ROOT/"pi/catalog/skills/daily-tasks/scripts/journal-task-sync").is_file())
        self.assertIn("logging-best-practices", catalog["external"])

    def test_runtime_versions_are_pinned(self):
        deps = json.loads((ROOT/"pi/runtime/package.json").read_text())["dependencies"]
        self.assertEqual(deps, {"@earendil-works/pi-coding-agent": "1.1.0"})
        for package in ("runtime", "manager", "renderer"):
            manifest = json.loads((ROOT/"pi"/package/"package.json").read_text())
            lock = json.loads((ROOT/"pi"/package/"package-lock.json").read_text())
            self.assertEqual(manifest["dependencies"], lock["packages"][""]["dependencies"])

    def test_foreign_service_is_not_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            root = home/"private"
            installer.prepare(root)
            unit = home/"config/systemd/user/pi-port-memory.service"
            unit.parent.mkdir(parents=True)
            unit.write_text("foreign service")
            with patch.object(Path, "home", return_value=home), patch.dict(installer.os.environ, {"XDG_CONFIG_HOME": str(home/"config")}):
                with self.assertRaises(ValueError):
                    installer.configure(root)
            self.assertEqual(unit.read_text(), "foreign service")
            self.assertFalse((root/"install.json").exists())


if __name__ == "__main__":
    unittest.main()
