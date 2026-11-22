"""Source gates for fixes that live in AppKit wiring no unit test can drive: each reads the Swift file that held a
user-reported defect and fails on the shape that shipped it (docs/incidents.md names the rows).

    python3 -m unittest discover -s scripts -p 'test_*.py'

Each gate matches the code's syntax (a whole statement or a function body), never a bare identifier, so a comment
that mentions the fix cannot satisfy it.
"""

import json
import re
import shutil
import subprocess
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


class PreviewRoundTripGateTests(unittest.TestCase):
    def test_leaving_preview_scrolls_back_to_the_line_after_the_refill(self):
        """Every Command-3 round trip left the editor about a third higher (paragraph 50, 33, 23, 15; 2026-11-22,
        in 4.11.0): disablePreview scaled the ratio saved on entry by the editor's height before refillEditArea's
        queued fill, a layout estimate (11402 pt for a 16762 pt note). Entry keeps the top line, and the exit scrolls
        to it in a block queued after the refill, the ratio only a fallback."""
        text = source("Controllers/ViewController+Editor.swift")
        enable = code_lines(function_body(text, "func enablePreview()"))
        self.assertIn("savedEditorTopPlace = editorTopPlace()", enable)
        disable = function_body(text, "func disablePreview()")
        refill = disable.find("self.refillEditArea(suppressSave: true)")
        place = disable.find("if shouldUseStoredState, let place = storedTopPlace {")
        self.assertGreater(refill, 0, "the refill moved; update this gate with it")
        self.assertGreater(place, refill, "the line is restored after the refill is queued")
        queued = code_lines(block_after(disable, disable.index("DispatchQueue.main.async", place)))
        self.assertEqual(queued, ["[weak self] in", "self?.scrollEditor(toTopPlace: place)"])
        self.assertRegex(disable[place:], r"(?s)^if shouldUseStoredState, let place = storedTopPlace \{.*?\} else \{\s*self\.scrollEditor\(toRatio: ratioToRestore\)")

class PreviewShowsTheNoteGateTests(unittest.TestCase):
    def test_scrolls_to_the_editor_wait_for_the_page_to_show_the_note(self):
        """The first Command-3 on a long note showed its top, and the split pane went back to the top after a round
        trip through preview (2026-11-22, in 4.11.0): enablePreview's scroll ran on a page that was ready but still
        held the preloaded blank note, and enableSplitViewMode never synced again because the scroll observer from
        before preview was still there. Both wait for the page to show the editor's note."""
        text = source("Controllers/ViewController+Editor.swift")
        enable = function_body(text, "func enablePreview()")
        at = enable.find("self?.editArea.markdownView?.scrollToLine(editorVisibleLine")
        self.assertGreater(at, 0, "the scroll moved; update this gate with it")
        self.assertRegex(enable[:at], r"editArea\.markdownView\?\.runWhenShowing\(note\) \{ \[weak self\] in\s*\Z")
        split = function_body(text, "private func enableSplitViewMode()")
        self.assertRegex(split, r"startSplitScrollSync\(\)[\s\S]*?editArea\.markdownView\?\.runWhenShowing\(note\) \{ \[weak self\] in\s*self\?\.syncPreviewToEditor\(\)")
        sync = code_lines(function_body(text, "private func syncPreviewToEditor()"))
        self.assertIn("lastSyncedEditorOffset = -1", sync)

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



class MarkupFontGateTests(unittest.TestCase):
    def test_markup_brackets_use_the_english_system_face(self):
        # #580: under a Simplified Chinese interface the plain system face hands `[` and `]` to
        # .CJKSymbolsFallbackSC and the editor drew a link's brackets as nothing. A test process runs in
        # English and cannot switch the face's language, so the shape is gated here.
        body = code_lines(function_body(source("Helpers/NotesTextProcessor.swift"), "public static var markupFont: NSFont"))
        self.assertTrue(any('CTFontCreateUIFontForLanguage(.system, size, "en" as CFString)' in line for line in body), body)
        self.assertFalse(any(line.startswith("NSFont.systemFont(") for line in body), body)


class PieColorGateTests(unittest.TestCase):
    def test_pie_slices_are_eight_colours_apart_from_the_panel(self):
        """Mermaid took pie1..3 from primary, secondary and tertiary, which are the paper and its panel, so slices 1
        and 3 matched each other and the page (2026-11-22). theme-config.js now sets eight slice colours per theme."""
        node = shutil.which("node")
        if node is None:
            self.skipTest("node is needed to resolve theme-config.js")
        program = (
            "global.window = {};"
            "eval(require('fs').readFileSync(process.argv[1], 'utf8'));"
            "const out = {};"
            "for (const k of ['light', 'dark']) out[k] = window.ThemeColors.getMermaidConfig(k === 'dark').themeVariables;"
            "console.log(JSON.stringify(out));"
        )
        themes = json.loads(subprocess.run(
            [node, "-e", program, str(ROOT / "Resources/DownView.bundle/js/theme-config.js")],
            check=True, capture_output=True, text=True).stdout)
        for name, v in themes.items():
            slices = [v[f"pie{i}"].upper() for i in range(1, 9)]
            self.assertEqual(len(set(slices)), 8, f"{name}: {slices}")
            self.assertNotIn(v["background"].upper(), slices, name)
            self.assertNotIn(v["primaryColor"].upper(), slices, name)
            self.assertEqual(v["pieOpacity"], "1", name)


if __name__ == "__main__":
    unittest.main()
