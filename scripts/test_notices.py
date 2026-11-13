"""THIRD-PARTY-NOTICES.md is what MiaoYan > Open Source Licenses shows, and what the bundled licenses ask the app
to carry. These gates fail when a vendored preview file or a Swift package is added or bumped without its entry.

    python3 -m unittest discover -s scripts -p 'test_*.py'
"""

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NOTICES = (ROOT / "THIRD-PARTY-NOTICES.md").read_text("utf-8")


class NoticesGateTests(unittest.TestCase):
    def test_every_vendored_preview_file_is_named(self):
        manifest = json.loads((ROOT / "Resources/DownView.bundle/js/vendor/MANIFEST.json").read_text("utf-8"))
        missing = [entry["name"] for entry in manifest["vendored"] if f"`js/{entry['name']}`" not in NOTICES]
        self.assertEqual(missing, [], "vendored files with no entry in THIRD-PARTY-NOTICES.md")

    def test_every_swift_package_is_named_at_its_resolved_version(self):
        resolved = json.loads(
            (ROOT / "MiaoYan.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text("utf-8")
        )
        headings = set(re.findall(r"^### (.+)$", NOTICES, re.MULTILINE))
        missing = []
        for pin in resolved["pins"]:
            name = pin["location"].rstrip("/").removesuffix(".git").rsplit("/", 1)[-1]
            version = pin["state"].get("version", "")
            if f"{name} {version}" not in headings:
                missing.append(f"{name} {version}")
        self.assertEqual(missing, [], "packages whose resolved version has no ### heading in THIRD-PARTY-NOTICES.md")

    def test_the_app_bundles_the_notices_file(self):
        project = (ROOT / "MiaoYan.xcodeproj/project.pbxproj").read_text("utf-8")
        self.assertRegex(project, r"/\* THIRD-PARTY-NOTICES\.md in Resources \*/,\n")


if __name__ == "__main__":
    unittest.main()
