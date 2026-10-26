"""Source gates for fixes that live in AppKit wiring no unit test can drive: each reads the Swift file that held a
user-reported defect and fails on the shape that shipped it (docs/incidents.md names the rows).

    python3 -m unittest discover -s scripts -p 'test_*.py'

Each gate matches the code's syntax (a whole statement or a function body), never a bare identifier, so a comment
that mentions the fix cannot satisfy it.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def source(path):
    return (ROOT / path).read_text("utf-8")


def block_after(text, start):
    """The text between the first `{` at or after `start` and its matching `}`, braces in comments skipped."""
    open_at = text.index("{", start)
    depth = 0
    i = open_at
    while i < len(text):
        if text.startswith("//", i):
            i = text.index("\n", i)
            continue
        if text.startswith("/*", i):
            i = text.index("*/", i) + 2
            continue
        char = text[i]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[open_at + 1 : i]
        i += 1
    raise ValueError("unbalanced braces")


def function_body(text, signature):
    at = text.find(signature)
    if at < 0:
        raise AssertionError(f"{signature} not found")
    return block_after(text, at)


def code_lines(body):
    return [line.split("//", 1)[0].strip() for line in body.splitlines() if line.split("//", 1)[0].strip()]


class KeyMonitorGateTests(unittest.TestCase):
    def test_the_editor_key_monitor_passes_every_key_on_but_return_from_the_list(self):
        """#491: the window's local keyDown monitor returned nil for every key its handler claimed, which swallowed
        Command-C system-wide on macOS Tahoe. The monitor ends by returning the event, and its one `return nil` sits
        in an `if` that names kVK_Return (Return from the list or sidebar has already moved focus)."""
        text = source("Controllers/ViewController.swift")
        monitor = re.search(r"NSEvent\.addLocalMonitorForEvents\(matching: NSEvent\.EventTypeMask\.keyDown\)", text)
        self.assertIsNotNone(monitor, "the editor's keyDown monitor moved; update this gate with it")
        lines = code_lines(block_after(text, monitor.end()))
        self.assertRegex(lines[-1], r"^return (event|\$0)$", "the monitor must end by passing the event on")
        for index, line in enumerate(lines):
            if re.search(r"\breturn nil\b", line):
                guard = next((lines[j] for j in range(index - 1, -1, -1) if lines[j].startswith("if ")), "")
                self.assertTrue(
                    guard.endswith("{") and "kVK_Return" in guard and "return nil" not in guard,
                    f"`return nil` outside an `if ... kVK_Return ... {{` block: {line!r} after {guard!r}",
                )


class PreviewFrameGateTests(unittest.TestCase):
    def test_the_preview_is_sized_against_the_preview_pane_first(self):
        """#541: refreshEditArea sized the markdown view against editAreaScroll, which preview-only mode collapses to
        zero width, so reopening a closed window showed a blank preview. Every frame taken from editAreaScroll's
        bounds is the fallback after previewScrollView."""
        sites = []
        for path in ("Controllers/MainWindowController.swift", "Controllers/ViewController+Editor.swift",
                     "Views/EditTextView.swift"):
            for line in source(path).splitlines():
                code = line.split("//", 1)[0]
                if re.search(r"editAreaScroll\)?\.bounds", code):
                    sites.append((path, code.strip()))
        self.assertIn("Controllers/MainWindowController.swift", {path for path, _ in sites})
        for path, code in sites:
            self.assertRegex(code, r"previewScrollView.*?\?\?\s*[\w?.]*editAreaScroll", f"{path}: {code}")
        refresh = function_body(source("Controllers/MainWindowController.swift"), "func refreshEditArea(")
        self.assertRegex(refresh, r"let newFrame = \(vc\.previewScrollView \?\? vc\.editAreaScroll\)\.bounds")


class SingleModeGateTests(unittest.TestCase):
    def test_single_mode_is_cleared_before_launch_loads_the_library_and_on_quit(self):
        """#503: opening one .md file stored single mode in UserDefaults, and a Command-Q or crash kept it, so the next
        launch loaded only that file's folder and the library's notes and folders seemed gone. Launch clears it
        before Storage loads projects, and terminate clears it again."""
        text = source("Controllers/AppDelegate.swift")
        clear = "UserDefaultsManagement.clearSingleMode()"
        launch = code_lines(function_body(text, "func applicationWillFinishLaunching("))
        self.assertIn(clear, launch)
        loads = [i for i, line in enumerate(launch) if re.search(r"\bstorage\.load(Projects|Documents)\(", line)]
        self.assertTrue(loads, "launch no longer loads the library here; move this gate with it")
        self.assertLess(launch.index(clear), loads[0])
        self.assertIn(clear, code_lines(function_body(text, "func applicationWillTerminate(")))


if __name__ == "__main__":
    unittest.main()
