"""scripts/ui_script.py must refuse the daily app's bundle id and must not call an empty compare a pass.

    python3 -m unittest discover -s scripts -p 'test_*.py'
"""

import contextlib
import io
import plistlib
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ui_script  # noqa: E402


def fake_app(root: Path, bundle: str) -> Path:
    app = root / "MiaoYan.app"
    (app / "Contents").mkdir(parents=True)
    (app / "Contents" / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": bundle}))
    return app


class UIScriptTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def test_run_refuses_the_daily_bundle_id_without_launching(self):
        app = fake_app(self.root, "com.tw93.miaoyan")
        with mock.patch.object(ui_script.subprocess, "run") as launched:
            code = ui_script.run_once(app, self.root / "s.txt", self.root, self.root / "out", False, 5)
        self.assertEqual(code, 1)
        launched.assert_not_called()

    def test_run_refuses_an_app_with_no_info_plist(self):
        with mock.patch.object(ui_script.subprocess, "run") as launched:
            code = ui_script.run_once(self.root / "Missing.app", self.root / "s.txt", self.root, self.root / "out", False, 5)
        self.assertEqual(code, 1)
        launched.assert_not_called()

    def test_run_accepts_the_qa_bundle_id(self):
        app = fake_app(self.root, ui_script.SCRIPT_BUNDLE_ID)
        library = self.root / "lib"
        library.mkdir()
        with mock.patch.object(ui_script.subprocess, "run") as launched:
            ui_script.run_once(app, self.root / "s.txt", library, self.root / "out", False, 5)
        launched.assert_called_once()

    def test_compare_fails_when_no_capture_exists(self):
        old, new = self.root / "old", self.root / "new"
        old.mkdir()
        new.mkdir()
        self.assertEqual(ui_script.compare(old, new, self.root), 1)

    def test_compare_fails_when_only_one_side_captured(self):
        old, new = self.root / "old", self.root / "new"
        old.mkdir()
        new.mkdir()
        (old / "a.png").write_bytes(b"x")
        self.assertEqual(ui_script.compare(old, new, self.root), 1)

    def test_compare_stops_on_a_failed_run(self):
        with mock.patch.object(ui_script, "run_once", return_value=1) as run, mock.patch.object(
            sys, "argv", ["ui_script.py", "compare", "a.app", "b.app", "s.txt", "--out", str(self.root)]
        ):
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(ui_script.main(), 1)
        self.assertEqual(run.call_count, 1)


if __name__ == "__main__":
    unittest.main()
