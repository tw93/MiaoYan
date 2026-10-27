"""The incident ledger's checker and the risk tiers (scripts/check_incidents.py, scripts/risk_tier.py), each proved
able to fail on a known-bad sample before its pass on the real ledger counts.

    python3 -m unittest discover -s scripts -p 'test_*.py'
"""

import fnmatch
import importlib.util
import unittest
import datetime
import io
import sys
import tempfile
from contextlib import redirect_stdout
from unittest import mock
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent


def load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


incidents = load("check_incidents")
risk = load("risk_tier")

HEADER = (
    "## Incidents\n\n| ID | Reported | Symptom | Introduced | Fixed | Layer | Caught by |\n"
    "|---|---|---|---|---|---|---|\n"
)
GOOD = "| I-01 | 2026-07-17 | A note took another note's text | unknown | 205dde53 | review | `KnownCatcher` |\n"


class IncidentLedgerTests(unittest.TestCase):
    def check(self, rows, check_commits=False):
        return incidents.problems(HEADER + rows, "docs/incidents.md", {"KnownCatcher"}, check_commits)

    def test_a_complete_row_passes(self):
        self.assertEqual(self.check(GOOD), [])

    def test_each_broken_cell_is_named(self):
        cases = {
            "layer x is not one of": GOOD.replace("| review |", "| x |"),
            "catcher `MissingCatcher` is not a test or gate": GOOD.replace("KnownCatcher", "MissingCatcher"),
            "no catcher named": GOOD.replace("`KnownCatcher`", "a test"),
            "Fixed is not a commit": GOOD.replace("205dde53", "later"),
            "Introduced is not a commit": GOOD.replace("unknown", "soon"),
            "Reported is not a date": GOOD.replace("2026-07-17", "July 17"),
            "I-01 repeats": GOOD + GOOD,
            "expected 7 cells": GOOD.replace(" review |", ""),
        }
        for message, rows in cases.items():
            with self.subTest(message):
                found = self.check(rows)
                self.assertEqual(len(found), 1, found)
                self.assertIn(message, found[0])

    def test_a_commit_that_does_not_resolve_fails_in_a_full_clone(self):
        if incidents.is_shallow():
            self.skipTest("commits are not resolvable in a shallow clone")
        self.assertEqual([], self.check(GOOD, check_commits=True))
        found = self.check(GOOD.replace("205dde53", "0000000"), check_commits=True)
        self.assertEqual(["docs/incidents.md:5: Fixed 0000000 does not resolve"], found)

    def test_rows_outside_the_incidents_section_are_not_read(self):
        found = list(incidents.rows("## Layers\n| a | b |\n" + HEADER + GOOD))
        self.assertEqual(1, len(found))
        self.assertEqual(7, found[0][0])

    def test_every_catcher_kind_is_found_in_the_code(self):
        defined = incidents.defined_catchers()
        for name in (
            "testRefusesCrossNoteWholeBufferSave",  # XCTest in MiaoYanTests
            "testCardTextDropsMarkupAndKeepsTwoLines",  # XCTest in the MiaoYanCore package
            "test_every_catcher_kind_is_found_in_the_code",  # Python test under scripts/
            "version-consistency",  # CI job id
        ):
            with self.subTest(name):
                self.assertIn(name, defined)
        self.assertTrue(incidents.is_defined("scripts/check_incidents.py", defined))
        self.assertFalse(incidents.is_defined("scripts/no_such_gate.py", defined))
        # Step names and keys inside a job are not job ids.
        self.assertNotIn("steps", defined)
        self.assertNotIn("runs-on", defined)

    def test_the_real_ledger_passes(self):
        text = incidents.LEDGER.read_text("utf-8")
        self.assertGreater(sum(1 for _ in incidents.rows(text)), 0)
        found = incidents.problems(text, "docs/incidents.md", incidents.defined_catchers(), not incidents.is_shallow())
        self.assertEqual(found, [])


class RiskTierTests(unittest.TestCase):
    def names(self, *paths):
        return [name for name, _, _ in risk.tiers_for(list(paths))]

    def test_a_change_takes_every_tier_it_reaches_highest_first(self):
        self.assertEqual(
            ["release", "notes", "export"],
            self.names("Business/HtmlManager.swift", "Business/Storage.swift", ".github/workflows/ci.yml"),
        )

    def test_the_sensitive_surfaces_are_never_default(self):
        for path, tier in {
            "scripts/build.sh": "release",
            "scripts/release-ci/update_appcast.sh": "release",
            "Info.plist": "release",
            "scripts/install.sh": "installer",
            "scripts/miaoyan": "installer",
            "Business/Note.swift": "notes",
            "Views/EditTextView.swift": "notes",
            "Business/CloudSyncManager.swift": "sync",
            "Resources/DownView.bundle/js/app.js": "export",
            "Packages/MiaoYanCore/Sources/MiaoYanCore/NoteText.swift": "core",
        }.items():
            with self.subTest(path):
                self.assertIn(tier, self.names(path))

    def test_docs_tests_and_ui_need_only_the_default_checks(self):
        self.assertEqual(
            [],
            self.names(
                "docs/incidents.md", "AGENTS.md", "MiaoYanTests/NoteSaveDebounceTests.swift",
                "Shell/ShellPalette.swift", "Packages/MiaoYanCore/Tests/MiaoYanCoreTests/NoteSearchTests.swift",
            ),
        )

    def test_every_tier_pattern_matches_a_tracked_file(self):
        # A pattern that matches nothing protects nothing: a rename would silently drop a file to the default tier.
        tracked = risk.git("ls-files")
        self.assertGreater(len(tracked), 100)
        for name, _, patterns in risk.TIERS:
            for pattern in patterns:
                with self.subTest(f"{name}: {pattern}"):
                    self.assertTrue(any(fnmatch.fnmatchcase(p, pattern) for p in tracked))


class BreakerTests(unittest.TestCase):
    """The incident circuit breaker in risk_tier.py: counted by Reported date, shown only beside a tier."""

    TODAY = datetime.date(2026, 10, 27)

    def ledger(self, dates_and_layers):
        rows = "\n".join(f"| I-{n:02d} | {day} | symptom | unknown | abc1234 | {layer} | `t` |"
                         for n, (day, layer) in enumerate(dates_and_layers, 1))
        text = ("# Incidents\n\n| ID | Reported | Symptom |\n|---|---|---|\n| X-01 | 2026-10-27 | outside |\n\n"
                "## Incidents\n\n| ID | Reported | Symptom | Introduced | Fixed | Layer | Caught by |\n"
                f"|---|---|---|---|---|---|---|\n{rows}\n")
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "incidents.md"
        path.write_text(text, "utf-8")
        return path

    def recent(self, dates_and_layers):
        return risk.recent_incidents(today=self.TODAY, ledger=self.ledger(dates_and_layers))

    def test_only_rows_reported_in_the_last_seven_days_count(self):
        recent = self.recent([("2026-10-27", "unit"), ("2026-10-21", "unit"), ("2026-10-20", "unit"),
                              ("2026-10-28", "unit")])
        # Day 0 and day 6 count; day 7 has aged out; a future date (a clock set back) is never counted.
        self.assertEqual(["I-01", "I-02"], [ident for ident, _ in recent])

    def test_it_trips_at_five_rows_and_names_the_layers_by_count(self):
        self.assertIsNone(risk.breaker_line(self.recent([("2026-10-26", "unit")] * 4)))
        line = risk.breaker_line(self.recent([("2026-10-26", "review")] * 3 + [("2026-10-25", "unit")] * 2))
        self.assertIn("5 incidents in the last 7 days", line)
        self.assertIn(risk.BREAKER_GATE, line)
        self.assertTrue(line.endswith("(review 3, unit 2)"), line)

    def test_a_missing_ledger_never_trips_it(self):
        self.assertEqual([], risk.recent_incidents(today=self.TODAY, ledger=Path("/nonexistent/incidents.md")))

    def test_it_is_printed_only_beside_a_tier(self):
        tripped = [("I-01", "unit")] * risk.BREAKER_ROWS
        tiered = next(p for _, _, patterns in risk.TIERS for p in patterns if "*" not in p)
        for paths, shown in ((["zz-untiered/none.txt"], False), ([tiered], True)):
            with self.subTest(paths=paths), \
                    mock.patch.object(risk, "recent_incidents", return_value=tripped), \
                    mock.patch.object(sys, "argv", ["risk_tier.py", *paths]), \
                    redirect_stdout(io.StringIO()) as out:
                risk.main(paths) if risk.main.__code__.co_argcount else risk.main()
                self.assertEqual(shown, "risk: breaker" in out.getvalue(), out.getvalue())


if __name__ == "__main__":
    unittest.main()
