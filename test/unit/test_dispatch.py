"""Pins the pure core of skills/implement/scripts/dispatch: the functions a
plan's Topology table and RANGE argument pass through before a dispatch file
is ever written. The module has no .py extension, so it is loaded with an
explicit SourceFileLoader rather than a plain import — see _load_dispatch
below.
"""

import io
import os
import shutil
import subprocess
import tempfile
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

# Phase headings and **Verification** fields for verification_join —
# find_owner's neighbour, so this sits beside its own fixtures rather than
# reusing ROW_PLAN, whose phase 3 carries the old '- cases: —' grammar.
# Phase 4's How field quotes a fenced '- joins:' bullet as an example, for a
# reader, before phase 4's own real Verification field — proving the walk
# is fence-aware and does not pick up the wrong number.
PLAN_WITH_JOIN = """# Join Plan

## Phases

### Phase 1. First phase

**Verification**
- proved by: phase 4

### Phase 2. Second phase

**Verification**
- proved by: phase 4

### Phase 3. Third phase

**Verification**
- proved by: phase 4

### Phase 4. The join

**How**
- an example quoted for a reader, not a real bullet:
```markdown
- joins: phases 99-99
```

**Verification**
- joins: phases 1-3
- cases: TC-1, TC-2
"""

# A '- joins:' shaped bullet that sits under a field other than
# **Verification**, unfenced — proves the walk latches on the field heading
# and does not just scan the whole phase for the bullet's shape.
PLAN_JOIN_BULLET_OUTSIDE_FIELD = """# Not The Field

## Phases

### Phase 1. Only phase

**How**
- joins: phases 1-1

**Verification**
- proved by: phase 2
"""

# The row TC-11 through TC-15 dispatch against: three rows — phase 1 alone,
# phases 2-3-4 together, phase 5 alone — with only phase 3 written out, since
# dispatch only ever cuts the requested RANGE, never the row's other phases.
ROW_PLAN = """# Row Plan

## Topology

| Phases | Implementer | Why the boundary is here |
|---|---|---|
| 1 | Sonnet | why_row_one |
| 2, 3, 4 | Opus | why_row_two_three_four |
| 5 | Sonnet | why_row_five |

## Phases

### Phase 3. Phase three title

**Becomes true**
- phase_3_becomes_true

**Changes**
- src/phase3.ts

**Depends on**
- —

**How**
- plain implementation

**Do not touch**
- —

**Frozen for later phases**
- —

**Verification**
- cases: —

**Steps**
- [ ] step 3
"""


def _run_git(*args):
    subprocess.run(["git", *args], check=True, capture_output=True, text=True)


def _new_repo(case):
    """A throwaway git repository, cleaned up when `case` tears down — never
    the real project checkout, and never its own .ai-workflow workspace."""
    repo = tempfile.mkdtemp(prefix="test-dispatch-")
    case.addCleanup(shutil.rmtree, repo, ignore_errors=True)
    _run_git("init", "-q", "-b", "main", repo)
    _run_git("-C", repo, "config", "user.email", "fixture@example.com")
    _run_git("-C", repo, "config", "user.name", "fixture")
    with open(os.path.join(repo, "README.md"), "w", encoding="utf-8") as fh:
        fh.write("# fixture\n")
    _run_git("-C", repo, "add", "README.md")
    _run_git("-C", repo, "commit", "-q", "-m", "chore: initial commit")
    return repo


def _write_plan(repo, text=ROW_PLAN):
    path = os.path.join(repo, "plan.md")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    return path


def _run_dispatch(repo, *args):
    return subprocess.run(
        [SCRIPT_PATH, *args], cwd=repo, capture_output=True, text=True)


def _workspace_dir(repo):
    return os.path.join(repo, ".ai-workflow", "run", "plan")


def _read(path):
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def _extract_section(body, heading):
    """The text between '## <heading>' and the next '## ' heading, exclusive
    of both — None when the heading is absent."""
    lines = body.splitlines()
    start = None
    for i, line in enumerate(lines):
        if line.strip() == "## %s" % heading:
            start = i + 1
            break
    if start is None:
        return None
    end = len(lines)
    for i in range(start, len(lines)):
        if lines[i].startswith("## "):
            end = i
            break
    return "\n".join(lines[start:end])


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
        self.assertIsNotNone(owner)
        self.assertEqual(owner.model, "Opus")
        self.assertIsNone(spanning)


class VerificationJoinTests(unittest.TestCase):
    def test_returns_range_for_a_join_phase(self):
        lines = PLAN_WITH_JOIN.splitlines()
        self.assertEqual(sd.verification_join(lines, 4), (1, 3))

    def test_returns_none_for_an_ordinary_phase(self):
        lines = PLAN_WITH_JOIN.splitlines()
        self.assertIsNone(sd.verification_join(lines, 1))

    def test_fenced_example_is_not_read_as_the_real_bullet(self):
        # Phase 4's How field quotes '- joins: phases 99-99' inside a fence
        # before its own real '- joins: phases 1-3' bullet. Only the real
        # one should come back.
        lines = PLAN_WITH_JOIN.splitlines()
        result = sd.verification_join(lines, 4)
        self.assertNotEqual(result, (99, 99))
        self.assertEqual(result, (1, 3))

    def test_bullet_outside_the_verification_field_is_ignored(self):
        lines = PLAN_JOIN_BULLET_OUTSIDE_FIELD.splitlines()
        self.assertIsNone(sd.verification_join(lines, 1))

    def test_absent_phase_returns_none(self):
        lines = PLAN_WITH_JOIN.splitlines()
        self.assertIsNone(sd.verification_join(lines, 99))


class TestsBranchTests(unittest.TestCase):
    def test_derives_branch_from_slug_and_range(self):
        self.assertEqual(
            sd.tests_branch("/tmp/plans/the-row.md", 1, 8),
            "run/the-row/tests-1-8",
        )

    def test_basename_only_the_slug_ignores_directory(self):
        by_full_path = sd.tests_branch("/a/b/c/tester-plan.md", 2, 4)
        by_bare_name = sd.tests_branch("tester-plan.md", 2, 4)
        self.assertEqual(by_full_path, "run/tester-plan/tests-2-4")
        self.assertEqual(by_full_path, by_bare_name)


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


class DispatchRowCLITests(unittest.TestCase):
    """TC-11 through TC-15: dispatch addressing one phase of a multi-phase
    Topology row, end to end through the real script — each case builds its
    own throwaway repository, never the real project checkout or its own
    .ai-workflow workspace."""

    def test_tc11_a_range_contained_in_one_row_is_dispatched_alone(self):
        repo = _new_repo(self)
        plan = _write_plan(repo)
        proc = _run_dispatch(repo, plan, "3")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        body = _read(os.path.join(_workspace_dir(repo), "dispatch-3-3.md"))
        self.assertIn("# Implementer dispatch — phases 3-3", body)
        self.assertIn("Opus", body)
        self.assertIn("why_row_two_three_four", body)

    def test_tc12_the_frozen_contract_is_the_range_before_the_row(self):
        repo = _new_repo(self)
        plan = _write_plan(repo)
        proc = _run_dispatch(repo, plan, "3")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        body = _read(os.path.join(_workspace_dir(repo), "dispatch-3-3.md"))
        self.assertIn("contracts/1-1.md", body)
        self.assertNotIn("contracts/1-2.md", body)

    def test_tc13_a_sibling_report_from_the_same_row_is_not_listed(self):
        repo = _new_repo(self)
        plan = _write_plan(repo)
        ws = _workspace_dir(repo)
        os.makedirs(ws, exist_ok=True)
        with open(os.path.join(ws, "report-1-1.md"), "w", encoding="utf-8") as fh:
            fh.write("# report before the row\n")
        with open(os.path.join(ws, "report-2-2.md"), "w", encoding="utf-8") as fh:
            fh.write("# report from a sibling phase of the same row\n")
        proc = _run_dispatch(repo, plan, "3")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        body = _read(os.path.join(ws, "dispatch-3-3.md"))
        self.assertIn("report-1-1.md", body)
        self.assertNotIn("report-2-2.md", body)

    def test_tc14_worktree_names_the_path_or_names_the_current_checkout(self):
        repo_with = _new_repo(self)
        plan_with = _write_plan(repo_with)
        proc_with = _run_dispatch(
            repo_with, plan_with, "3", "--worktree", "/some/path")
        self.assertEqual(proc_with.returncode, 0, proc_with.stderr)
        body_with = _read(
            os.path.join(_workspace_dir(repo_with), "dispatch-3-3.md"))
        section_with = _extract_section(body_with, "Where you work")
        self.assertIsNotNone(section_with)
        self.assertIn("/some/path", section_with)
        self.assertNotIn("<<< FILL", section_with)

        repo_without = _new_repo(self)
        plan_without = _write_plan(repo_without)
        proc_without = _run_dispatch(repo_without, plan_without, "3")
        self.assertEqual(proc_without.returncode, 0, proc_without.stderr)
        body_without = _read(
            os.path.join(_workspace_dir(repo_without), "dispatch-3-3.md"))
        section_without = _extract_section(body_without, "Where you work")
        self.assertIsNotNone(section_without)
        self.assertIn("current checkout", section_without)
        self.assertNotIn("<<< FILL", section_without)

    def test_tc15_a_range_spanning_two_rows_still_refuses(self):
        repo = _new_repo(self)
        plan = _write_plan(repo)
        proc = _run_dispatch(repo, plan, "4-5")
        self.assertEqual(proc.returncode, 3, proc.stdout + proc.stderr)
        self.assertIn("span more than one Topology row", proc.stderr)
        self.assertIn("phases 2, 3, 4", proc.stderr)
        self.assertIn("phases 5", proc.stderr)


if __name__ == "__main__":
    unittest.main()
