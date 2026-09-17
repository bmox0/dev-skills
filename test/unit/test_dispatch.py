"""Pins the pure core of skills/implement/scripts/dispatch: the functions a
plan's Topology table and RANGE argument pass through before a dispatch file
is ever written. The module has no .py extension, so it is loaded with an
explicit SourceFileLoader rather than a plain import — see _load_dispatch
below.
"""

import io
import os
import unittest
from contextlib import redirect_stderr
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_file_location

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT_PATH = os.path.normpath(
    os.path.join(HERE, "..", "..", "skills", "implement", "scripts", "dispatch")
)


def _load_dispatch():
    # spec_from_file_location alone returns a spec whose .loader is None for
    # a file with no recognised extension, and module_from_spec then fails
    # with AttributeError: 'NoneType' object has no attribute 'loader' —
    # verified against this tree. The explicit loader= argument is what
    # avoids it.
    name = "dispatch_under_test"
    loader = SourceFileLoader(name, SCRIPT_PATH)
    spec = spec_from_file_location(name, SCRIPT_PATH, loader=loader)
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


sd = _load_dispatch()


PLAN_WITH_TOPOLOGY = """# Some Plan

## Topology

| Phases | Implementer | Why the checkpoint is here |
|---|---|---|
| 1-3 | Sonnet | first checkpoint |
| 4-8 | Sonnet | last one before the final gate |

## Phases

| Not | A | Topology | Table |
|---|---|---|---|
| x | y | z | w |
"""

# No blank line between the topology table's last row and the next heading,
# and none between that heading and the second table: this is what makes the
# case actually exercise the fence/break logic rather than being caught
# incidentally by the "a blank line ends the table" bookkeeping.
PLAN_TWO_TABLES = """# Plan

## Topology

| Phases | Implementer | Why the checkpoint is here |
|---|---|---|
| 1-3 | Sonnet | first checkpoint |
| 4-8 | Sonnet | last one before the final gate |
## Not Topology
| Phases | Implementer | Why the checkpoint is here |
|---|---|---|
| 20-21 | Opus | should never appear |
"""

PLAN_NO_TOPOLOGY = """# Plan

## Something Else

| A | B |
|---|---|
| 1 | 2 |
"""


class ParseRangeTests(unittest.TestCase):
    def test_expands_a_dash_separated_pair(self):
        self.assertEqual(sd.parse_range("2-4"), (2, 4))

    def test_expands_a_bare_number_to_itself_twice(self):
        self.assertEqual(sd.parse_range("5"), (5, 5))

    def test_rejects_swapped_bounds(self):
        stderr = io.StringIO()
        with redirect_stderr(stderr):
            with self.assertRaises(SystemExit) as cm:
                sd.parse_range("4-2")
        self.assertEqual(cm.exception.code, 2)
        self.assertIn("bad RANGE:", stderr.getvalue())

    def test_rejects_non_numeric_range(self):
        stderr = io.StringIO()
        with redirect_stderr(stderr):
            with self.assertRaises(SystemExit) as cm:
                sd.parse_range("abc")
        self.assertEqual(cm.exception.code, 2)
        self.assertIn("bad RANGE:", stderr.getvalue())


class IsSeparatorTests(unittest.TestCase):
    def test_separator_row_is_true(self):
        self.assertTrue(sd.is_separator(sd.split_row("|---|---|")))

    def test_data_row_is_false(self):
        cells = sd.split_row("| 1 | 1-3 | Sonnet | first checkpoint |")
        self.assertFalse(sd.is_separator(cells))


class ParseTableTests(unittest.TestCase):
    TABLE_LINES = [
        "| Phases | Implementer | Why the checkpoint is here |",
        "|---|---|---|",
        "| 1 | Sonnet | first |",
        "| 2, 3, 4 | Sonnet | second |",
        "| 5-6 | Opus | third |",
    ]

    def test_yields_three_segments_first_and_last_present_no_separator(self):
        segments = sd.parse_table(self.TABLE_LINES)
        self.assertEqual(len(segments), 3)
        self.assertEqual(segments[0].why, "first")
        self.assertEqual(segments[-1].why, "third")

    def test_derives_first_and_last_from_phases_cell(self):
        segments = sd.parse_table(self.TABLE_LINES)
        by_why = {s.why: s for s in segments}
        self.assertEqual((by_why["second"].first, by_why["second"].last), (2, 4))
        self.assertEqual((by_why["first"].first, by_why["first"].last), (1, 1))


class TopologySegmentsTests(unittest.TestCase):
    def test_two_segment_table_boundaries_inclusive(self):
        segments = sd.topology_segments(PLAN_WITH_TOPOLOGY.splitlines())
        self.assertEqual(len(segments), 2)
        self.assertEqual((segments[0].first, segments[0].last), (1, 3))
        self.assertEqual((segments[1].first, segments[1].last), (4, 8))

    def test_a_later_sections_table_does_not_leak_in(self):
        segments = sd.topology_segments(PLAN_TWO_TABLES.splitlines())
        self.assertEqual(
            [s.why for s in segments],
            ["first checkpoint", "last one before the final gate"],
        )

    def test_no_topology_heading_returns_none_not_empty_list(self):
        result = sd.topology_segments(PLAN_NO_TOPOLOGY.splitlines())
        self.assertIsNone(result)


class FindOwnerTests(unittest.TestCase):
    def setUp(self):
        self.segments = [
            sd.Segment("1-3", 1, 3, "Sonnet", "first checkpoint"),
            sd.Segment("4-8", 4, 8, "Opus", "last one before the final gate"),
        ]

    def test_exact_match_returns_owner_with_correct_model(self):
        owner, spanning = sd.find_owner(self.segments, 4, 8)
        self.assertIsNotNone(owner)
        self.assertEqual(owner.model, "Opus")
        self.assertIsNone(spanning)

    def test_range_spanning_two_segments(self):
        owner, spanning = sd.find_owner(self.segments, 2, 5)
        self.assertIsNone(owner)
        self.assertEqual({s.phases_raw for s in spanning}, {"1-3", "4-8"})

    def test_range_strictly_inside_one_segment_but_not_equal_bounds(self):
        owner, spanning = sd.find_owner(self.segments, 5, 6)
        self.assertIsNone(owner)
        self.assertEqual(spanning, [])


class ExtractWrittenPathTests(unittest.TestCase):
    def test_extracts_path_after_a_warning_line(self):
        stdout = "warning: something noted\nwrote /tmp/x/brief-1-3.md: 42 lines\n"
        self.assertEqual(sd.extract_written_path(stdout), "/tmp/x/brief-1-3.md")

    def test_ignores_a_path_shaped_first_line_that_is_not_a_wrote_line(self):
        stdout = (
            "/tmp/not-a-wrote-line/looks/like/a/path\n"
            "wrote /tmp/x/brief-1-3.md: 42 lines\n"
        )
        self.assertEqual(sd.extract_written_path(stdout), "/tmp/x/brief-1-3.md")

    def test_raises_systemexit_when_no_wrote_line(self):
        stderr = io.StringIO()
        with redirect_stderr(stderr):
            with self.assertRaises(SystemExit):
                sd.extract_written_path("no wrote line here at all\n")


if __name__ == "__main__":
    unittest.main()
