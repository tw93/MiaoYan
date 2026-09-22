#!/usr/bin/env python3
"""Exercise project skill mirrors without touching the installed skills."""
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("sync-agent-skills.sh")
NAMES = ("appstore", "code-review", "github-ops", "lint", "release")


class SkillMirrorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "repo"
        (self.root / "scripts").mkdir(parents=True)
        shutil.copyfile(SCRIPT, self.root / "scripts/sync-agent-skills.sh")
        self.sources = self.root / ".agents/skills"
        self.mirrors = self.root / ".claude/skills"
        self.mirrors.mkdir(parents=True)
        for name in NAMES:
            source = self.sources / name
            source.mkdir(parents=True)
            (source / "SKILL.md").write_text(name + "\n")
            (self.mirrors / name).symlink_to(Path("../../.agents/skills") / name)

    def run_sync(self, mode="--check"):
        return subprocess.run(["bash", str(self.root / "scripts/sync-agent-skills.sh"), mode], capture_output=True, text=True)

    def test_internal_links_are_preserved(self):
        for mode in ("--check", "--write", "--check"):
            result = self.run_sync(mode)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(all((self.mirrors / name).is_symlink() for name in NAMES))

    def test_regular_copies_still_sync(self):
        for name in NAMES:
            (self.mirrors / name).unlink()
        self.assertNotEqual(self.run_sync().returncode, 0)
        self.assertEqual(self.run_sync("--write").returncode, 0)
        self.assertEqual(self.run_sync().returncode, 0)

    def test_wrong_internal_target_rejected(self):
        target = self.mirrors / "appstore"
        target.unlink()
        target.symlink_to(self.sources / "lint")
        for mode in ("--check", "--write"):
            self.assertNotEqual(self.run_sync(mode).returncode, 0)

    def test_external_target_rejected_even_with_equal_bytes(self):
        outside = Path(self.temp.name) / "outside"
        shutil.copytree(self.sources / "appstore", outside)
        target = self.mirrors / "appstore"
        target.unlink()
        target.symlink_to(outside)
        for mode in ("--check", "--write"):
            self.assertNotEqual(self.run_sync(mode).returncode, 0)
        self.assertEqual((outside / "SKILL.md").read_text(), "appstore\n")

    def test_linked_parent_rejected(self):
        moved = self.root / "elsewhere"
        self.mirrors.rename(moved)
        self.mirrors.symlink_to(moved)
        self.assertNotEqual(self.run_sync().returncode, 0)

    def test_linked_canonical_file_rejected(self):
        source = self.sources / "appstore/SKILL.md"
        source.unlink()
        source.symlink_to(self.sources / "lint/SKILL.md")
        self.assertNotEqual(self.run_sync().returncode, 0)


if __name__ == "__main__":
    unittest.main()
