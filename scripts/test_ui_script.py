"""scripts/ui_script.py must refuse the daily app's bundle id, must not call an empty compare a pass, and must see
a change in colour: until 2026-11-25 compare called every pair identical, because Pillow's getbbox() reads only the
alpha band of an RGBA difference and two opaque window captures differ only in colour.

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



try:
    from PIL import Image
except ImportError:  # CI's Python may not have Pillow; compare needs it anyway.
    Image = None


@unittest.skipIf(Image is None, "Pillow is not installed")
class CompareTests(unittest.TestCase):
    def run_compare(self, old_pixel, new_pixel):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name, pixel in (("old", old_pixel), ("new", new_pixel)):
                folder = root / name
                folder.mkdir()
                image = Image.new("RGBA", (40, 30), (250, 249, 246, 255))
                image.putpixel((12, 7), pixel)
                image.save(folder / "shot.png")
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = ui_script.compare(root / "old", root / "new", root)
            return code, output.getvalue(), (root / "diff-shot.png").exists()

    def test_an_opaque_capture_that_changed_colour_is_reported(self):
        code, output, wrote_diff = self.run_compare((250, 249, 246, 255), (20, 20, 20, 255))
        self.assertEqual(code, 1, output)
        self.assertIn("1 pixels differ in (12, 7, 13, 8)", output)
        self.assertTrue(wrote_diff)

    def test_a_capture_that_changed_only_transparency_is_reported(self):
        code, output, _ = self.run_compare((250, 249, 246, 255), (250, 249, 246, 0))
        self.assertEqual(code, 1, output)

    def test_identical_captures_are_identical(self):
        code, output, wrote_diff = self.run_compare((250, 249, 246, 255), (250, 249, 246, 255))
        self.assertEqual(code, 0, output)
        self.assertIn("shot.png: identical", output)
        self.assertFalse(wrote_diff)


if __name__ == "__main__":
    unittest.main()
