#!/usr/bin/env python3
"""The pipeline's CLI: the plan parser and the project's rules in docs/spec/.

Usage: pipeline.py spec check [--base REV] PLAN
       pipeline.py spec write [--base REV] PLAN
       pipeline.py spec list
       pipeline.py spec show ID
       pipeline.py approve [--json] PLAN
       pipeline.py plan review [--json] PLAN
       pipeline.py plan approve PLAN --revision HASH --by NAME --words TEXT [--acceptor NAME --authority TEXT]
       pipeline.py accept PLAN --by NAME --words TEXT
       pipeline.py status [--json] [--provider NAME] [--current | PLAN]
       pipeline.py workflow [--stage STAGE] [--json]
       pipeline.py GUIDE [--plan PLAN]
       pipeline.py plan status [--note TEXT] PLAN VALUE
       pipeline.py plan base [--note TEXT] PLAN REF
       pipeline.py build start [--base REF] [--provider NAME] [--worktree PATH] [--json] [--note TEXT] PLAN
       pipeline.py phase start|done [--note TEXT] PLAN N
       pipeline.py phase report --became T --commit SHA [...] [--check COMMAND OUTCOME ...] PLAN N
       pipeline.py owner PLAN PATH
       pipeline.py grant [--note TEXT] PLAN N PATH
       pipeline.py decision --question Q --from S --answer A --why W --cost C PLAN
       pipeline.py brief implementer PLAN N | brief judge|round|reviewer|fix PLAN | brief verify [--cases N,N] PLAN   --provider NAME [--note TEXT]
       pipeline.py gate start [--note TEXT] PLAN
       pipeline.py finding --kind K --text T [--where F:L] [--source S] [--again ID] PLAN
       pipeline.py review complete --assignment NAME --range BASE..HEAD PLAN
       pipeline.py result --case N --outcome passed|failed|not-reached [--capture C] [--detail T] PLAN
       pipeline.py fix start|done PLAN | fix report --became T [--commit SHA ...] PLAN
       pipeline.py verdict pass|round|question PLAN --report T [--decide ID ACTION REASON] [--note T CAUSE] [--evidence-note TEXT]
       pipeline.py verdict evidence-owed PLAN --owed reviewer|verify [--case N ...] --report T
       pipeline.py land draft PLAN | land [now] PLAN | land accept --note T PLAN | land revert [--note T] PLAN
       pipeline.py page (--guide TEXT | --guide-file PATH) [--message TEXT] PLAN
       pipeline.py page --show PLAN
       pipeline.py note add|edit|drop PLAN ...
       pipeline.py round start [--conflict T] PLAN | round report --became T [--commit SHA ...] PLAN | round done PLAN
       pipeline.py finish [--merged] PLAN
       pipeline.py run new|check PLAN | run show [--json] PLAN
       pipeline.py executor show --provider NAME [PLAN] [--json]

check reads the plan's `## Spec` section against docs/spec/ as it is at the
base (--base, else the base in the plan's Status line, else HEAD) and reports
every problem as `<file>:<line>: <message>`, exit 1; that includes what write
would drop or alter in a base area file (`docs/spec/<area>.md:<line>`) and an
archive record of the plan's file name already at the base, and a plan without
a `# ` title. write runs check, refuses when the working tree's docs/spec/ is
not the base plus what this plan's earlier archive record (its Done and Spec)
produces (compared as parsed, so blank lines and the `-`/`*` scenario marker do
not matter), makes docs/spec/ equal to the base plus the section, and
writes the archive record. A bad argument is exit 2.

gate start, fix done and round done run the plan's `[checks].full` outside the plan
lock, recording each command's result as it ends in a run that is unfinished until
the last one; other commands work meanwhile. Status names the owning transition
and whether to wait, confirm ownership, or retry it. A retry after the prior work
stops runs the whole suite, or reuses matching completed checks before closure.
build start, compilation and plan approval pick a port under one project-wide lock.

Standalone task entry snapshots project defaults and the selected release.
Run new copies the latest local run (else its example). Run check prints
problems as `<code>: … — fix: …`; run show prints approved values and any drift.
Executor show selects the current project pair before plan approval and the
frozen snapshot afterward. Briefs use the recorded provider or require --provider,
and expose the assigned tier/model/effort for explicit dispatch.

list prints every area (`<area> — <title>`), its description indented under it, and its rules, indented
(`  <area>#<rule> — <statement>`), from the working tree. show prints the rule
`<area>#<rule>` (heading, Why, scenarios), then each archive record whose Spec
section names it, newest file name first: `## archive/<file> — <plan title>`
and that section's entry for the rule. An ID that is not a rule is
`pipeline.py spec: no rule <id>` on stderr, exit 1.

approve compiles a plan into `<slug>.json` (the state) after a strict check, whose
problems are `<plan>:<line>: <message>`, exit 1; it renders the code-owned lines
back into the plan and the plan's row in its epic, and adopts a plan that has no
state as its file stands. Compilation never records consent. `plan review` shows
the complete planning content and run configuration together. `plan approve`
records the human's unchanged words for that revision. Approval starts nothing;
a separate `build start` command opens the build. Reapproval
preserves progress. `accept` binds the designated acceptor's words to the current
judge, land and page before setting passed. Protected transitions and finish
independently verify those records and their freshness. Every write refuses (`<code>: <message> — fix: <fix>`,
exit 1) while the plan file differs from its last render. status prints one plan
or all; plan status and plan base change the plan's code-owned fields. Library
use: `writing(plan)` yields the locked state and saves and renders on exit;
`set_plan`, `set_phase`, `record` and `ready_phases` work on it.
"""

import argparse
import contextlib
import datetime
import difflib
import errno
import fcntl
from functools import cache
import hashlib
import io
import json
import os
import re
import secrets
import shlex
import subprocess
import sys
import shutil
import socket
import stat
import tempfile
import tomllib
from pathlib import Path
from urllib.parse import unquote

sys.dont_write_bytecode = True

PACKAGE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))


def standalone_bundle():
    if os.path.basename(os.path.dirname(PACKAGE)) == "releases" and os.path.isfile(os.path.join(PACKAGE, "release.json")):
        from runweld_release import installed_root
        return installed_root(__file__)
    return None


def skill_path(tree, skill):
    if standalone_bundle() is not None:
        rel = f"workflow/{skill.removeprefix('runweld ')}/GUIDE.md" if skill.startswith("runweld ") else skill
        if re.fullmatch(r"workflow/[a-z0-9-]+/GUIDE\.md", rel) and os.path.isfile(builtin := os.path.join(PACKAGE, rel)):
            return builtin
    return os.path.join(tree, os.path.expanduser(skill))

def phase_instruction(tree, item):
    from runweld_release import GUIDE_COMMANDS
    if item in GUIDE_COMMANDS:
        return f"runweld {item}"
    if item.startswith("runweld "):
        return item
    if re.fullmatch(r"workflow/[a-z0-9-]+/GUIDE\.md", item):
        return "runweld " + Path(item).parent.name
    return skill_path(tree, item)


HISTORY = "This is history; the rules that hold now are in `docs/spec/`."
README = (
    "# Spec\n\n"
    "The rules this product must keep, one file per area. The script writes these\n"
    "files from plans; a rule is changed through a plan or `runweld spec`, not by\n"
    "hand. `archive/` holds one record per plan: why each rule changed.\n"
)
ID = r"[a-z0-9][a-z0-9-]*"
ENTRY = re.compile(rf"^([+~-])\s+({ID}(?:#{ID})?)(?:\s+—\s+(.*\S))?\s*$")
KEY = re.compile(r"^\s+(Why|About|Done):\s*(.*?)\s*$")
RULE_HEAD = re.compile(rf"^### ({ID}) — (.*\S)\s*$")


class Fail(Exception):
    pass


def git(*args, check=True, cwd=None):
    try:
        r = subprocess.run(["git", *args], capture_output=True, text=True, cwd=cwd)
    except OSError as e:
        r = subprocess.CompletedProcess(["git", *args], 128, "", str(e))
    if check and r.returncode:
        raise Fail(r.stderr.strip() or "git failed")
    return r


def parse_area(text, problems=None):
    """Area file text -> {title, about, rules: [{id, statement, why, scenarios}]}.

    What render_area would not reproduce is listed in problems as (line, message).
    """
    problems = [] if problems is None else problems
    area = {"title": "", "about": "", "rules": []}
    about = []
    rule = None
    for n, line in enumerate(text.splitlines(), 1):
        m = RULE_HEAD.match(line)
        if line.startswith("# ") and not area["title"]:
            area["title"] = line[2:].strip()
        elif m:
            rule = {"id": m[1], "statement": m[2], "why": "", "scenarios": [], "line": n, "has_why": False}
            area["rules"].append(rule)
        elif rule is None:
            about.append(line)
        elif line.startswith("Why:"):
            if rule["has_why"]:
                problems.append((n, f"rule {rule['id']}: a second Why: line, write keeps one"))
            rule["why"], rule["has_why"] = line[4:].strip(), True
        elif line.startswith(("- ", "* ")):
            rule["scenarios"].append(line[2:].strip())
        elif line.strip():
            problems.append((n, f"write would drop this line: {line.strip()}"))
    if not area["title"]:
        problems.append((1, "no `# ` title line"))
    for r in area["rules"]:
        if not r["has_why"]:
            problems.append((r["line"], f"rule {r['id']}: no Why: line"))
        elif not r["why"]:
            problems.append((r["line"], f"rule {r['id']}: Why: is empty"))
    area["about"] = "\n".join(about).strip()
    return area


def render_area(area):
    out = [f"# {area['title']}", ""]
    if area["about"]:
        out += [area["about"], ""]
    for r in area["rules"]:
        out += [f"### {r['id']} — {r['statement']}", "", f"Why: {r['why']}", ""]
        if r["scenarios"]:
            out += [f"- {s}" for s in r["scenarios"]] + [""]
    return "\n".join(out).rstrip("\n") + "\n"


def normalised(path, text):
    """What a file means: an area file as parsed, anything else as written."""
    if text is None or not is_area_path(path):
        return text
    probs = []
    area = parse_area(text, probs)
    # what parsing drops counts too: a stray line is an edit
    return {**area, "rules": [{k: v for k, v in r.items() if k != "line"} for r in area["rules"]],
            "dropped": [m for _, m in probs]}


def is_area_path(rel):
    return rel.endswith(".md") and "/" not in rel and rel != "README.md"


def areas_of(tree, problems=None):
    """{rel path: text} -> {area-id: area}; area files' problems as (path, line, message)."""
    out = {}
    for rel, text in sorted(tree.items()):
        if is_area_path(rel):
            probs = []
            out[rel[:-3]] = parse_area(text, probs)
            if problems is not None:
                problems += [(f"docs/spec/{rel}", n, m) for n, m in probs]
    return out


def tree_at(rev, cwd=None):
    """docs/spec/ as committed at rev: {rel path: text}. An unborn HEAD has none."""
    if git("rev-parse", "--verify", "-q", f"{rev}^{{commit}}", check=False, cwd=cwd).returncode:
        if rev == "HEAD":
            return {}
        raise Fail(f"unknown base {rev}")
    names = git("ls-tree", "-r", "--full-tree", "--name-only", rev, "--", "docs/spec/", cwd=cwd).stdout.split("\n")
    return {p[len("docs/spec/"):]: git("show", f"{rev}:{p}", cwd=cwd).stdout for p in names if p}


def tree_on_disk(root):
    """docs/spec/ in the working tree, untracked files too: {rel path: text}."""
    d = os.path.join(root, "docs", "spec")
    out = {}
    for base, _, names in os.walk(d):
        for n in names:
            if not n.startswith("."):
                path = os.path.join(base, n)
                out[os.path.relpath(path, d)] = open(path, encoding="utf-8", errors="surrogateescape").read()
    return out


def spec_on_disk(root):
    return areas_of(tree_on_disk(root))


def render_tree(tree, spec):
    """What write leaves of tree: the areas of spec rendered, the rest kept."""
    out = {p: t for p, t in tree.items() if not is_area_path(p)}
    out.setdefault("README.md", README)
    out.update({f"{n}.md": render_area(a) for n, a in spec.items()})
    return out


def sections(lines, dups=None):
    """Level-2 sections: {heading: (first body line number, [body lines])}.

    A `## ` line inside a ``` fence is body. A repeated heading keeps the first
    section and is listed in dups as (line, heading).
    """
    out, name, fenced = {}, None, False
    for i, line in enumerate(lines, 1):
        if line.lstrip().startswith("```"):
            fenced = not fenced
        if line.startswith("## ") and not fenced:
            name = line[3:].strip()
            if name in out:
                if dups is not None:
                    dups.append((i, name))
                name = None
            else:
                out[name] = (i + 1, [])
        elif name is not None:
            out[name][1].append(line)
    return out


def fenced(lines):
    """Per line: True for a ``` fence line and every line inside a fence."""
    out, inside = [], False
    for line in lines:
        fence = line.lstrip().startswith("```")
        inside ^= fence
        out.append(inside or fence)
    return out


def done_raw(body):
    items, last = {}, None
    for line in body:
        m = re.match(r"^(\d+)\.\s+(.*)$", line)
        if m:
            last = int(m[1])
            items[last] = m[2]
        elif last is not None and line.startswith((" ", "\t")) and line.strip():
            items[last] += " " + line.strip()
    return items


YOU_CHECK = r"\s*—\s*you check\.?\s*$"


def done_items(body):
    return {n: re.sub(YOU_CHECK, "", t).strip() for n, t in done_raw(body).items()}


def done_list(body):
    """The Done items for the state: [{n, text, you_check}]."""
    return [{"n": n, "text": re.sub(YOU_CHECK, "", t).strip(), "you_check": bool(re.search(YOU_CHECK, t))} for n, t in done_raw(body).items()]


def parse_section(start, body, problems):
    """Entries of the section: [{line, sign, id, statement, keys}] or 'none'."""
    text = [l for l in body if l.strip()]
    if not text:
        problems.append((start - 1, "the `## Spec` section is empty; write `none` when no rule changes"))
    if len(text) == 1 and text[0].strip() == "none":
        return "none"
    entries = []
    for n, line in enumerate(body, start):
        if not line.strip():
            continue
        m = ENTRY.match(line)
        k = KEY.match(line)
        if m:
            entries.append({"line": n, "sign": m[1], "id": m[2], "statement": m[3], "keys": {}})
        elif k and entries:
            entries[-1]["keys"][k[1]] = (k[2], n)
        else:
            problems.append((n, f"not an entry or a Why:/About:/Done: line: {line.strip()}"))
    return entries


def cited(entry, done, problems):
    raw = entry["keys"]["Done"]
    nums = []
    for part in raw[0].split(","):
        if not part.strip().isdigit() or int(part) < 1:
            problems.append((raw[1], f"Done: {raw[0]!r} is not a list of item numbers"))
            return []
        if int(part) not in done:
            problems.append((raw[1], f"Done: cites item {part.strip()}, the plan has {len(done)}"))
        nums.append(int(part))
    return nums


def apply(plan_lines, base_spec):
    """-> (merged spec or None for `none`, problems [(line, message)])."""
    problems = []
    dups = []
    secs = sections(plan_lines, dups)
    problems += [(n, f"a second `## {name}` section") for n, name in dups if name == "Spec"]
    if "Spec" not in secs:
        return None, [(1, "no `## Spec` section; write `none` when no rule changes")]
    entries = parse_section(*secs["Spec"], problems)
    if entries == "none":
        return None, problems
    done = done_items(secs.get("Done", (0, []))[1])
    spec = {k: {**v, "rules": [dict(r) for r in v["rules"]]} for k, v in base_spec.items()}
    entries.sort(key=lambda e: not (e["sign"] == "+" and "#" not in e["id"]))

    for e in entries:
        keys, where = e["keys"], e["line"]
        area_id, _, rule_id = e["id"].partition("#")
        if e["sign"] != "+" and not rule_id:
            problems.append((where, f"{e['sign']} takes a rule ID (area#rule), got {e['id']}"))
            continue
        if e["sign"] != "-" and not e["statement"]:
            problems.append((where, f"{e['id']}: no statement after ' — '"))
            continue
        if not rule_id:
            if area_id in spec:
                problems.append((where, f"area {area_id} already exists"))
            else:
                if "About" not in keys:
                    problems.append((where, f"{area_id}: no About: line"))
                elif not keys["About"][0]:
                    problems.append((where, f"{area_id}: About: is empty"))
                spec[area_id] = {"title": e["statement"], "about": keys.get("About", ("",))[0], "rules": []}
            continue
        if "Why" not in keys:
            problems.append((where, f"{e['id']}: no Why: line"))
        elif not keys["Why"][0]:
            problems.append((where, f"{e['id']}: Why: is empty"))
        nums = cited(e, done, problems) if "Done" in keys and e["sign"] != "-" else []
        area = spec.get(area_id)
        rule = next((r for r in area["rules"] if r["id"] == rule_id), None) if area else None
        if e["sign"] == "+":
            if area is None:
                problems.append((where, f"area {area_id} does not exist and is not added here"))
            elif rule:
                problems.append((where, f"rule {e['id']} already exists"))
            elif "Done" not in keys:
                problems.append((where, f"{e['id']}: an added rule needs a Done: line"))
            else:
                area["rules"].append({
                    "id": rule_id, "statement": e["statement"],
                    "why": keys.get("Why", ("",))[0],
                    "scenarios": [done[n] for n in nums if n in done],
                })
        elif rule is None:
            problems.append((where, f"rule {e['id']} does not exist"))
        elif e["sign"] == "-":
            area["rules"].remove(rule)
        else:
            rule["statement"], rule["why"] = e["statement"], keys.get("Why", ("",))[0]
            if "Done" in keys:
                rule["scenarios"] = [done[n] for n in nums if n in done]
    return spec, problems


def archive_record(plan_lines):
    title = next((l for l in plan_lines if l.startswith("# ")), None)
    secs = sections(plan_lines)
    out = [HISTORY, ""]
    if title:
        out += [title, ""]
    def add(name):
        out.extend([f"## {name}", *secs[name][1]])
        while not out[-1].strip():
            out.pop()
        out.append("")

    for name in ("Result", "Approach", "Out of scope"):
        if name in secs:
            add(name)
    # one code block: a formatter reads `+` and `-` at a line start as list markers
    out += ["## Done and Spec", "", "```text"]
    for name in ("Done", "Spec"):
        if name in secs:
            add(name)
    out[-1:] = ["```", ""]
    return "\n".join(out).rstrip("\n") + "\n"


def record_parts(lines):
    """An archive record's (Done body or None, Spec body), from its `Done and Spec` block or, in an older record, its sections."""
    secs = sections(lines)
    if "Done and Spec" in secs:
        body = secs["Done and Spec"][1]
        fences = [i for i, l in enumerate(body) if l.lstrip().startswith("```")]
        inner = sections(body[fences[0] + 1:fences[-1]] if len(fences) > 1 else [])
    else:
        inner = secs
    return inner["Done"][1] if "Done" in inner else None, inner.get("Spec", (0, []))[1]


def base_of(plan_lines, given):
    if given:
        return given
    for l in plan_lines:
        m = re.match(r"^Status:.*\bbase\s+`([^`]+)`", l)
        if m:
            return m[1]
    return "HEAD"


def run(command, plan, given_base, cwd=None):
    try:
        root = git("rev-parse", "--show-toplevel", cwd=cwd).stdout.strip()
    except Fail:
        print("pipeline.py spec: not inside a git repository", file=sys.stderr)
        return 1
    fix = "restore the plan Markdown or pass its correct path"
    text = read_required(plan, "no-plan", fix, optional=True)
    if text is None:
        print(f"no-plan: {plan} does not exist — fix: {fix}", file=sys.stderr)
        return 2
    plan_lines = text.splitlines()
    name = os.path.basename(plan)
    base_rev = base_of(plan_lines, given_base)
    try:
        tree = tree_at(base_rev, root)
        head = tree_at("HEAD", root)
    except Fail as e:
        print(f"{plan}:1: {e}")
        return 1
    # this plan's own committed write also moves docs/spec/; the checks below judge that one
    moved = sorted(p for p in tree.keys() | head.keys() if tree.get(p) != head.get(p))
    def stale(paths):
        return (f"{plan}:1: docs/spec/ changed in commits after the base {base_rev} ({', '.join(paths)}): "
                "if the default branch moved, pass --base $(git merge-base <default branch> HEAD) "
                "or put it on the Status line; if a commit on this branch edited it by hand, revert that commit")

    out = [stale(moved)] if moved and "archive/" + name not in head else []
    base_problems = []
    base = areas_of(tree, base_problems)
    spec, problems = apply(plan_lines, base)
    if spec is not None:
        out += [f"{p}:{n}: {m}" for p, n, m in base_problems]
        if "archive/" + name in tree:
            out.append(f"{plan}:1: the archive record {name} already exists at the base")
    if not any(l.startswith("# ") for l in plan_lines):
        problems.append((1, "no `# ` title line"))
    out += [f"{plan}:{n}: {m}" for n, m in sorted(problems)]
    if out:
        print("\n".join(out))
        return 1
    if command == "check":
        return 0

    work = tree_on_disk(root)
    expected = tree
    record = work.get("archive/" + name)
    title = next((l for l in plan_lines if l.startswith("# ")), None)
    # a record with another title belongs to another plan
    mine = record is not None and next((l for l in record.splitlines() if l.startswith("# ")), None) == title
    if mine:
        rdone, rspec = record_parts(record.splitlines())
        done = sections(plan_lines).get("Done", (0, []))[1] if rdone is None else rdone
        old, probs = apply(["## Done", *done, "## Spec", *rspec], base)
        if old is not None and not probs:
            expected = {**render_tree(tree, old), "archive/" + name: record}
    differ = sorted(p for p in work.keys() | expected.keys()
                    if normalised(p, work.get(p)) != normalised(p, expected.get(p)))
    if differ:
        if all(work.get(p) == head.get(p) for p in differ):
            # committed, so there is nothing to commit or discard
            print(stale(differ))
            return 1
        if mine:
            why = "it is not what this plan's earlier write left (a hand edit, or the base moved); commit or discard it first"
        else:
            why = "it is another plan's uncommitted write or a hand edit; commit or discard it first"
        for p in differ:
            print(f"{plan}:1: docs/spec/{p} differs from the base, and {why}")
        return 1

    d = os.path.join(root, "docs", "spec")
    if spec is None:
        # `none` after an earlier write: put docs/spec/ back to the base
        for p in work.keys() - tree.keys():
            os.remove(os.path.join(d, p))
        for p, text in tree.items():
            if work.get(p) != text:
                open(os.path.join(d, p), "w", encoding="utf-8").write(text)
        for base_dir, _, _ in sorted(os.walk(d), reverse=True):
            if not os.listdir(base_dir):
                os.rmdir(base_dir)
        return 0
    os.makedirs(os.path.join(d, "archive"), exist_ok=True)
    readme = os.path.join(d, "README.md")
    if not os.path.exists(readme):
        open(readme, "w", encoding="utf-8").write(README)
    for n in {k[:-3] for k in work if is_area_path(k)} - spec.keys():
        os.remove(os.path.join(d, n + ".md"))
    for n, area in spec.items():
        open(os.path.join(d, n + ".md"), "w", encoding="utf-8").write(render_area(area))
    open(os.path.join(d, "archive", name), "w", encoding="utf-8").write(archive_record(plan_lines))
    return 0


def read_spec(command, rule_id):
    try:
        root = git("rev-parse", "--show-toplevel").stdout.strip()
    except Fail:
        print("pipeline.py spec: not inside a git repository", file=sys.stderr)
        return 1
    spec = spec_on_disk(root)
    if command == "list":
        for name, area in spec.items():
            print(f"{name} — {area['title']}")
            for l in area["about"].splitlines():
                print(f"  {l}")
            for r in area["rules"]:
                print(f"  {name}#{r['id']} — {r['statement']}")
        return 0
    name, _, rid = rule_id.partition("#")
    rule = next((r for r in spec.get(name, {"rules": []})["rules"] if r["id"] == rid), None)
    if rule is None:
        print(f"pipeline.py spec: no rule {rule_id}", file=sys.stderr)
        return 1
    print(f"{rule_id} — {rule['statement']}")
    print(f"Why: {rule['why']}")
    for sc in rule["scenarios"]:
        print(f"- {sc}")
    adir = os.path.join(root, "docs", "spec", "archive")
    for fn in sorted(os.listdir(adir), reverse=True) if os.path.isdir(adir) else []:
        lines = open(os.path.join(adir, fn), encoding="utf-8").read().splitlines()
        body = record_parts(lines)[1]
        entry, hit = [], False
        for l in body:
            m = ENTRY.match(l)
            if m:
                hit = m[2] == rule_id
            if hit and l.strip():
                entry.append(l)
        if entry:
            title = next((l[2:] for l in lines if l.startswith("# ")), fn)
            print(f"\n## archive/{fn} — {title}")
            print("\n".join(entry))
    return 0


# ---- the plan's state: approve, the state file, the render, status ----------

PLAN_STATUSES = ["draft", "approved", "building", "at the human gate", "passed", "merged"]
PHASE_STATUSES = ["waiting", "in progress", "done"]
LIVE = ("building", "at the human gate", "passed")
STATUS_LINE = re.compile(r"^Status: (.*?) · branch `([^`]*)` · base `([^`]*)`\s*$")
PHASE_HEAD = re.compile(r"^### (\d+)\.\s+(.+?)\s+—\s+`(waiting|in progress|done)`\s*$")
EPIC_LINE = re.compile(r"^Epic:\s*`?([^`\s]+)`?\s*·\s*row\s+(\d+)\s*$")
FIELD = re.compile(r"^(Territory|Skills|Spec|Waits for):\s*(.*?)\s*$")
RENDERED = "Rendered from `{}` by `pipeline.py`: change statuses by its commands; edit the text, then run `pipeline.py approve`."
REQUIRED = ["Result", "Approach", "Out of scope", "Phases", "Checks", "Done", "Spec"]


class Refuse(Exception):
    """One or more `<code>: <message> — fix: <fix>` diagnostics; exit 1."""

    def __init__(self, code, message, fix):
        super().__init__(message)
        self.diags = [(code, message, fix)]


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_required(path, code, fix, *, optional=False, newline=None):
    try:
        with open(path, encoding="utf-8", newline=newline, opener=lambda name, flags: os.open(name, flags | os.O_NONBLOCK)) as f:
            if not stat.S_ISREG(os.fstat(f.fileno()).st_mode):
                raise Refuse(code, f"{path} must be a readable regular file", fix)
            text = f.read()
    except FileNotFoundError:
        if optional and not os.path.lexists(path):
            return None
        raise Refuse(code, f"{path} does not exist", fix)
    except IsADirectoryError:
        raise Refuse(code, f"{path} must be a readable regular file", fix)
    except UnicodeDecodeError as e:
        raise Refuse(code, f"{path} is not valid UTF-8 ({e.reason})", fix)
    except (OSError, ValueError) as e:
        raise Refuse(code, f"cannot read {path} ({e})", fix)
    if not text.strip():
        raise Refuse(code, f"{path} is empty", fix)
    if "\0" in text:
        raise Refuse(code, f"{path} contains a NUL character", fix)
    return text


def plan_paths(plan):
    """-> (plan .md, state .json, lock), all absolute."""
    from runweld_release import history_path
    md = str(history_path(plan))
    if not md.endswith(".md"):
        raise Refuse("bad-plan", f"{plan} is not a .md file", "pass the plan file")

    # Resolve directory aliases, not the file itself, so a lock always guards its replacements.
    md = os.path.join(os.path.realpath(os.path.dirname(md)), os.path.basename(md))
    return md, md[:-3] + ".json", md[:-3] + ".json.lock"


def is_plan_file(fn):
    """A plan's own .md, excluding its companion files."""
    return fn.endswith(".md") and not re.search(r"\.(notes|judge|summary|guide|gate-log|brief-[\w-]+)\.md$", fn)


WORKFLOW_DIR = ".runweld/workflow"


def workflow_dir(project):
    root = Path(project) / WORKFLOW_DIR
    if any(p.is_symlink() or (p.exists() and not p.is_dir()) for p in (root.parent, root)):
        raise Refuse("workflow-path", f"{root} must be in real directories", "move the conflicting item aside and retry")
    return root


def workflow_subdir(path):
    if path.is_symlink() or (path.exists() and not path.is_dir()):
        raise Refuse("workflow-path", f"{path} must be a real directory", "move the conflicting item aside and retry")
    return path


def plan_root(md):
    from runweld_release import project_root
    root = project_root(Path(md).parent)
    if root is None:
        raise Refuse("no-repo", f"{md} is not inside a git repository", "keep plans inside the project")
    return str(root)


def plan_checkout(md):
    directory = Path(md).parent
    while not directory.is_dir() and directory != directory.parent:
        directory = directory.parent
    r = git("rev-parse", "--show-toplevel", check=False, cwd=directory)
    if r.returncode:
        raise Refuse("no-repo", f"{md} is not inside a git repository", "keep plans inside the project")
    return r.stdout.rstrip("\n")


def plan_directories(root, own=None):
    canonical = workflow_subdir(workflow_dir(root) / "plans")
    paths = [canonical]
    if own is not None:
        paths.append(Path(own).parent)
    return sorted({p.resolve() for p in paths if p.is_dir()})


def inventory(root, own=None):
    from runweld_release import task_folders
    plans = workflow_subdir(workflow_dir(root) / "plans")
    folders = {folder: folder / (name + ".md") for name, folder in task_folders(plans)}
    loose = [p for d in plan_directories(root, own) if d not in folders
             for p in sorted(d.iterdir()) if is_plan_file(p.name)]
    return loose + [path for path in folders.values() if os.path.lexists(path)]

def head_sha(md, tree=None):
    r = git("rev-parse", "HEAD", check=False, cwd=tree or os.path.dirname(md))
    return r.stdout.strip() if not r.returncode else None


def split_gate(lines):
    """-> (the part the CLI parses and renders, the hand-written `## Human gate` on)."""
    fenced = False
    for i, l in enumerate(lines):
        if l.lstrip().startswith("```"):
            fenced = not fenced
        elif l.startswith("## Human gate") and not fenced:
            return lines[:i], lines[i:]
    return lines, []


def read_plan(md):
    text = read_required(md, "no-plan", "restore the plan Markdown or pass its correct path")
    return split_gate(text.split("\n"))


def phase_brief_text(lines, n):
    mask = fenced(lines)
    i = next((k for k, line in enumerate(lines) if not mask[k] and (m := PHASE_HEAD.match(line)) and int(m[1]) == n), None)
    if i is None:
        return None
    j = next((k for k in range(i + 1, len(lines)) if lines[k].startswith("#") and not mask[k]), len(lines))
    return [f"## Phase {n}, verbatim from the plan", "", *lines[i:j], ""]


def head_hash(head):
    return hashlib.sha256(markdown_newlines("\n".join(head)).encode()).hexdigest()


def markdown_newlines(text):
    return text.replace("\r\n", "\n").replace("\r", "\n")


def norm(path):
    return path.strip().strip("/").removeprefix("./")


def overlaps(a, b):
    a, b = norm(a), norm(b)
    return a == b or a.startswith(b + "/") or b.startswith(a + "/")


def paths_of(value):
    if value.strip().lower().rstrip(".") in ("none", "nothing", ""):
        return []
    parts = re.findall(r"`([^`]*)`", value) or value.split(",")
    return [p.strip() for p in parts if p.strip()]


def header_of(lines):
    n = next((i for i, l in enumerate(lines) if l.startswith("## ")), len(lines))
    return lines[:n]


def was_compiled(head):
    header = header_of(head)
    return any(line.startswith("Rendered from `") and not masked for line, masked in zip(header, fenced(header)))


def epic_row(root, path, row):
    """-> (lines of the epic file, index of its row in the `## Plans` table or None)."""
    full = os.path.join(root, path)
    lines = read_required(full, "bad-epic", "restore the linked epic Markdown and its Plans table").split("\n")
    start, body = sections(lines).get("Plans", (0, []))
    mask = fenced(body)
    at = next((k for k, l in enumerate(body) if not mask[k] and re.match(rf"^\|\s*{row}\s*\|", l)), None)
    return lines, None if at is None else start - 1 + at


def check_epic(root, path, row):
    lines, i = epic_row(root, path, row)
    if i is None or not lines[i].rstrip().endswith("|") or lines[i].count("|") < 5:
        raise Refuse("bad-epic", f"{os.path.join(root, path)} has no complete Plans table row {row}",
                     "restore the linked epic and its numbered row")


def parse_plan(lines, root, *, check_references=True, history=None):
    """The plan's lines (as far as the CLI reads them) -> (plan dict, problems [(line, message)])."""
    problems = []
    bad = lambda n, m: problems.append((n, m))
    P = {"title": None, "status": None, "branch": None, "base": None, "epic": None, "level": None, "phases": []}
    mask = fenced(lines)
    for l, f in zip(lines, mask):
        if l.startswith("# ") and l[2:].strip() and not f:
            P["title"] = l[2:].strip()
            break
    else:
        bad(1, "no `# ` title line")
    for n, l in enumerate(header_of(lines), 1):
        if l.startswith("Status:") and not mask[n - 1]:
            m = STATUS_LINE.match(l)
            if not m:
                bad(n, "the Status line must read `Status: <status> · branch `<branch>` · base `<sha>``")
            else:
                P["status"], P["branch"], P["base"] = m[1], m[2], m[3]
                if m[1] not in PLAN_STATUSES and not m[1].startswith("http"):
                    bad(n, f"status {m[1]!r} is not one of {', '.join(PLAN_STATUSES)} or a merge-request link")
            break
    else:
        bad(1, "no Status line")
    for n, l in enumerate(header_of(lines), 1):
        if l.startswith("Epic:") and not mask[n - 1]:
            m = EPIC_LINE.match(l)
            if not m:
                bad(n, "the Epic line must read `Epic: <path> · row <n>`")
                break
            if check_references:
                check_epic(history or root, m[1], int(m[2]))
            P["epic"] = {"path": m[1], "row": int(m[2])}
            break
    dups = []
    secs = sections(lines, dups)
    for n, name in dups:
        bad(n, f"a second `## {name}` section")
    for name in REQUIRED:
        if name not in secs:
            bad(1, f"no `## {name}` section")
    if "Checks" in secs:
        start, body = secs["Checks"]
        for l in body:
            m = re.match(r"^\s*[-*]\s*Gate:\s*(small|normal)\b", l)
            if m:
                P["level"] = m[1]
        if P["level"] is None:
            bad(start - 1, "Checks has no `- Gate: small | normal — <why>` line")
    if "Done" in secs and not done_items(secs["Done"][1]):
        bad(secs["Done"][0] - 1, "the `## Done` section has no numbered item")
    if "Phases" in secs:
        parse_phases(*secs["Phases"], root, P, bad, check_references)
    return P, problems


def checked_plan(plan, head, root, *, check_references=True):
    parsed, problems = parse_plan(head, root, check_references=check_references)
    if problems:
        raise refuse_all([("bad-plan", f"{plan}:{n}: {message}",
                           "repair the plan Markdown, then run `pipeline.py approve`")
                          for n, message in sorted(problems)])
    return parsed


def parse_phases(start, body, root, P, bad, check_references):
    mask = fenced(body)
    heads = [i for i, l in enumerate(body) if l.startswith("### ") and not mask[i]]
    if not heads:
        bad(start - 1, "the `## Phases` section has no `### <n>. <task> — `waiting`` phase")
    for k, i in enumerate(heads):
        end = heads[k + 1] if k + 1 < len(heads) else len(body)
        m = PHASE_HEAD.match(body[i])
        at = start + i
        if not m:
            bad(at, "a phase heading must read `### <n>. <task> — `waiting | in progress | done``")
            continue
        if int(m[1]) != k + 1:
            bad(at, f"phase {m[1]} is number {k + 1} in the file; number them 1, 2, 3 in order")
        ph = {"n": int(m[1]), "title": m[2], "status": m[3], "fields": {}, "lines": {}}
        key = None
        for j in range(i + 1, end):
            f = None if mask[j] else FIELD.match(body[j])
            if f:
                key = f[1]
                ph["fields"][key], ph["lines"][key] = f[2], start + j
            elif key and not mask[j] and body[j].startswith((" ", "\t")) and body[j].strip():
                ph["fields"][key] += " " + body[j].strip()
            else:
                key = None
        for key in ("Territory", "Skills", "Spec", "Waits for"):
            if key not in ph["fields"]:
                bad(at, f"phase {m[1]} has no `{key}:` line")
        P["phases"].append(ph)
    nums = {p["n"] for p in P["phases"]}
    for ph in P["phases"]:
        f, ln = ph["fields"], ph["lines"]
        ph["territory"] = paths_of(f.get("Territory", ""))
        if not ph["territory"] and "Territory" in f:
            bad(ln["Territory"], f"phase {ph['n']}: Territory names no path")
        for t in ph["territory"]:
            if re.search(r"\s", t):
                bad(ln["Territory"], f"phase {ph['n']}: {t!r} is not a path; Territory lists directories or files")
        ph["skills"] = paths_of(f.get("Skills", ""))
        for sk in ph["skills"]:
            if sk.startswith("runweld "):
                from runweld_release import GUIDE_COMMANDS
                if sk.removeprefix("runweld ") not in GUIDE_COMMANDS:
                    bad(ln["Skills"], f"unknown Runweld instruction command: {sk}")
            elif "/" in sk or sk.endswith(".md"):
                if check_references and not os.path.exists(skill_path(root, sk)):
                    bad(ln["Skills"], f"phase {ph['n']}: skill {sk} does not exist")
            elif not re.fullmatch(r"[\w.:-]+", sk):
                bad(ln["Skills"], f"phase {ph['n']}: {sk!r} is neither a GUIDE.md path nor a skill name")
        ph["spec"] = paths_of(f.get("Spec", ""))
        for sp in ph["spec"]:
            if check_references and not os.path.exists(os.path.join(root, sp)):
                bad(ln["Spec"], f"phase {ph['n']}: area file {sp} does not exist")
        ph["waits"], ph["waits_text"] = [], ""
        w = f.get("Waits for", "")
        if w and w.strip().lower().rstrip(".").split()[:1] in (["nothing"], ["none"]):
            continue
        m = re.match(r"^(\d+(?:\s*(?:,|and|&)\s*\d+)*)\b\s*(.*)$", w)
        if not m:
            if "Waits for" in f:
                bad(ln["Waits for"], f"phase {ph['n']}: Waits for names phases by number, or says `nothing`")
            continue
        ph["waits"] = [int(x) for x in re.findall(r"\d+", m[1])]
        ph["waits_text"] = m[2].lstrip("—-– ").strip()
        for x in ph["waits"]:
            if x not in nums or x == ph["n"]:
                bad(ln["Waits for"], f"phase {ph['n']} waits for phase {x}, which is not another phase of this plan")
    graph = {p["n"]: [x for x in p["waits"] if x in nums] for p in P["phases"]}
    cycle = find_cycle(graph)
    if cycle:
        bad(next(p["lines"].get("Waits for", 1) for p in P["phases"] if p["n"] == cycle[0]),
            "Waits for forms a cycle: " + " → ".join(map(str, cycle)))
        return
    reach = {}
    def below(n):
        if n not in reach:
            reach[n] = set()
            for x in graph[n]:
                reach[n] |= {x} | below(x)
        return reach[n]
    for a in P["phases"]:
        for b in P["phases"]:
            if a["n"] < b["n"] and a["n"] not in below(b["n"]) and b["n"] not in below(a["n"]):
                hit = next(((x, y) for x in a["territory"] for y in b["territory"] if overlaps(x, y)), None)
                if hit:
                    bad(b["lines"].get("Territory", 1),
                        f"phases {a['n']} and {b['n']} both change {hit[0]} and {hit[1]}; one must wait for the other")


def find_cycle(graph):
    seen, stack = set(), []
    def dfs(n):
        if n in stack:
            return stack[stack.index(n):] + [n]
        if n in seen:
            return None
        seen.add(n)
        stack.append(n)
        for x in graph.get(n, []):
            c = dfs(x)
            if c:
                return c
        stack.pop()
    for n in graph:
        c = dfs(n)
        if c:
            return c


def graph_line(phases):
    depth = {}
    def d(n):
        if n not in depth:
            depth[n] = 1 + max([d(x) for x in by[n]["waits"]], default=-1)
        return depth[n]
    by = {p["n"]: p for p in phases}
    for n in by:
        d(n)
    return " → ".join(" ∥ ".join(str(n) for n in sorted(by) if depth[n] == k) for k in range(max(depth.values()) + 1))


def other_plans(root, md):
    """Plans beside this one from building to passed: [(name, status, parsed plan)]."""
    out = []
    for path in inventory(root, md):
        full = str(path)
        if full == md:
            continue
        try:
            head, _ = read_plan(full)
            P, _ = parse_plan(head, root, check_references=False)
            st = load_state(full)
        except Refuse:
            continue
        status = st["status"] if st else P["status"]
        if status and (status in LIVE or status.startswith("http")):
            out.append((full, status, P))
    return out


# -- state file, lock, render

@contextlib.contextmanager
def locked(plan):
    with open(plan_paths(plan)[2], "a") as lf:
        fcntl.flock(lf, fcntl.LOCK_EX)
        yield


def check_state_fields(value, fields, location, *, optional=()):
    """A `?` suffix marks fields that older records may omit."""
    if type(value) is not dict:
        return f"{location} must be an object"
    for key, expected in fields.items():
        required = not key.endswith("?") and key not in optional
        key = key.removesuffix("?")
        name = f"{location}.{key}"
        if key not in value:
            if required:
                return f"{name} is missing"
            continue
        if problem := check_state_value(value[key], expected, name):
            return problem


def check_state_value(value, expected, name):
    if isinstance(expected, dict):
        return check_state_fields(value, expected, name)
    if isinstance(expected, list):
        if type(value) is not list:
            return f"{name} must be a list"
        for i, item in enumerate(value):
            if problem := check_state_value(item, expected[0], f"{name}[{i}]"):
                return problem
    elif isinstance(expected, tuple):
        for kind in expected:
            if type(value) is (type(kind) if isinstance(kind, (dict, list)) else kind):
                return check_state_value(value, kind, name)
        return f"{name} must be " + " or ".join((kind if isinstance(kind, type) else type(kind)).__name__ for kind in expected)
    elif type(value) is not expected:
        return f"{name} must be a {expected.__name__}"


def state_problem(st, md):
    nullable_text = (str, type(None))
    nullable_int = (int, type(None))
    report = {"became": str, "skills": str, "interfaces": str, "checks": str, "commits": [str]}
    finished = {"head": str}
    core = {"version": int, "plan": str, "status": str, "branch": str, "base": str, "title": str, "level": str,
            "render_hash": str, "phases": [dict],
            "history": [{"at": str, "what": str, "from": nullable_text, "to": str, "note": nullable_text, "sha": nullable_text}]}
    records = {
        "done": [{"n": int, "text": str, "you_check": bool}],
        "cycles": [{"n": int, "kind": str, "level": nullable_text, "raised_by": [str],
                    "spec_refusal?": ([str], type(None)), "current_run?": int, "verify_cases?": dict,
                    "runs": [{"head": str, "at": str, "full": [str], "done?": bool, "pid?": nullable_int,
                              "commands": [{"command": str, "exit": int, "red": bool, "changed_tree": bool, "tail?": str}]}],
                    "findings": [{"id": str, "kind": str, "where": nullable_text, "source": nullable_text, "text": str, "again?": nullable_text}],
                    "results": [{"case": int, "outcome": str, "do": str, "see": str, "width": str, "detail": nullable_text,
                                 "capture": nullable_text, "at": str, "commit?": nullable_text}],
                    "fixes": [{"n": int, "from": str, "items": [str], "survived": [str], "report": (report, type(None)),
                               "done": (finished, type(None)), "verify_cases?": [int]}],
                    "reviews?": [{"range": str, "assignment": str, "at": str, "findings": int}]}],
        "lands": [{"n": int, "pre": str, "tip": str, "backup": str, "judge?": int,
                   "shape": [{"paths": [str], "message": str, "walkthrough": str, "sha": str}],
                   "difference": [str], "accepted": ({"note": str}, type(None)), "since?": nullable_text, "range_diff?": nullable_text}],
        "page": {"note": str, "message": nullable_text, "ending": {"how": str, "target": str}, "binding?": str},
        "rounds": [{"n": int, "by": str, "from": str, "notes": [int],
                    "report": (report, type(None)), "done": (finished, type(None))}],
        "notes": [{"n": int, "by": str, "text": str, "cause": str, "round": nullable_int, "source": nullable_text, "verdict": nullable_int}],
        "verdicts": [{"n": int, "kind": str, "head": str, "cycle": str, "at": str, "epoch": int, "report": str,
                      "decisions": [{"id": str, "action": str, "reason": str}], "notes": [int], "question": nullable_text,
                      "owed": nullable_text, "evidence_note?": nullable_text, "stop?": nullable_text, "answer?": nullable_text, "round?": nullable_int,
                      "stopped_notes?": [[str]], "owed_cases?": [int], "review_count?": int, "result_count?": int}],
        "land_stops": [{"lands": int, "kind": str, "message": str}],
        "decisions": [{"at": str, "phase": nullable_int, "by": str, "question": str, "source": str, "answer": str, "why": str, "cost": str}],
        "approvals": dict, "run": dict, "alloc": dict, "tree": str, "tail_hash": str, "cleanup_pending": str,
        "build_provider": str, "integration": {"how": str, "target": str, "landed": str, "commit?": str, "request?": str},
        "acceptance": {"page": str}, "request": {"tip": str, "acceptance": str}, "pushed": {"tip": str},
        "check_transition": {"cycle": str, "id": str, "command": str, "target": nullable_int, "host": nullable_text,
                             "child": ({"pgid": int, "start": str}, type(None)), "note?": nullable_text},
    }
    if problem := check_state_fields(st, {**core, **records}, "state", optional=records):
        return problem
    if st["version"] != 1 or st["plan"] != os.path.basename(md):
        return f"state must be version 1 for {os.path.basename(md)}"
    if st["status"] not in PLAN_STATUSES and not st["status"].startswith("http"):
        return "state.status must name a plan status or merge-request link"
    if st["level"] not in ("small", "normal") or not st["phases"]:
        return "state needs a gate level and at least one phase"
    if (page := st.get("page")) and page["ending"]["how"] not in CHOICES["finish", "how"]:
        return "state.page.ending.how must name a supported finish strategy"
    if finish := st.get("integration"):
        result = "request" if finish["how"] == "merge-request" else "commit"
        if finish["how"] not in CHOICES["finish", "how"] or not finish.get(result):
            return "state.integration needs the approved ending and its resulting commit or request"
    if (transition := st.get("check_transition")) and transition["command"] not in ("gate start", "fix done", "round done"):
        return "state.check_transition.command must name a full-check transition"
    for i, cycle in enumerate(st.get("cycles", [])):
        loc = f"state.cycles[{i}]"
        if cycle["kind"] not in ("gate", "round"):
            return f"{loc}.kind must be gate or round"
        if cycle["kind"] == "round" and not 1 <= cycle["n"] <= len(st.get("rounds", [])):
            return f"{loc}.n must refer to a recorded round"
        if "current_run" in cycle and not 0 <= cycle["current_run"] < len(cycle["runs"]):
            return f"{loc}.current_run must refer to a recorded check run"
        for assignment, cases in cycle.get("verify_cases", {}).items():
            if problem := check_state_value(cases, [int], f"{loc}.verify_cases.{assignment}"):
                return problem
        for j, finding in enumerate(cycle["findings"]):
            if finding["kind"] not in FINDING_KINDS:
                return f"{loc}.findings[{j}].kind must name a finding kind"
        for j, result in enumerate(cycle["results"]):
            if result["outcome"] not in ("failed", "not reached", "passed"):
                return f"{loc}.results[{j}].outcome must name a result outcome"
    for i, verdict in enumerate(st.get("verdicts", [])):
        loc = f"state.verdicts[{i}]"
        if verdict.get("stop") and "stopped_notes" not in verdict:
            return f"{loc}.stopped_notes is missing for a stopped verdict"
        if any(len(note) != 2 for note in verdict.get("stopped_notes", [])):
            return f"{loc}.stopped_notes must contain pairs of text and cause"
        if verdict["kind"] == "evidence-owed" and verdict["owed"] not in EVIDENCE_ROLES:
            return f"{loc}.owed must be {' or '.join(EVIDENCE_ROLES)} for an evidence-owed verdict"
    if (epic := st.get("epic")) is not None:
        if problem := check_state_fields(epic, {"path": str, "row": int}, "state.epic"):
            return problem
    for i, phase in enumerate(st["phases"], 1):
        fields = {"n": int, "status": str, "title": str, "territory": [str], "skills": [str],
                  "executor?": {"provider": str, "source": str, "tier": str, "model": str, "effort?": str},
                  "spec": [str], "waits": [int], "waits_text": str, "grants": [str], "report": dict}
        if problem := check_state_fields(phase, fields, f"state.phases[{i}]", optional=("grants", "report")):
            return problem
        if phase["n"] != i or phase["status"] not in PHASE_STATUSES:
            return f"state.phases[{i}] needs its consecutive phase number and a valid status"
        if any(n < 1 or n > len(st["phases"]) or n == i for n in phase["waits"]):
            return f"state.phases[{i}].waits must refer to other phases"
        if "report" in phase:
            fields = {**report, "check_outcomes": dict}
            if problem := check_state_fields(phase["report"], fields, f"state.phases[{i}].report", optional=("check_outcomes",)):
                return problem
    for kind, fields in (("plan", {"revision": str, "planning": [str], "run": str, "by": str, "words": str,
                                   "at": str, "acceptor": str, "authority": nullable_text}),
                         ("run", {"digest": str}),
                         ("summary", {"digest": str, "file": str, "planning": str, "run": str, "acceptor": str})):
        approvals = st.get("approvals", {})
        if kind in approvals:
            if problem := check_state_fields(approvals[kind], fields, f"state.approvals.{kind}"):
                return problem
    if "run" in st and (problems := run_diags(st["run"])):
        return f"state.run: {problems[0][1]}"


def missing_state(plan):
    js = plan_paths(plan)[1]
    return Refuse("not-compiled", f"{js} does not exist",
                  f"restore the compiled state, or run `pipeline.py approve {plan}` for an uncompiled plan")


def load_state(plan, *, required=False):
    md, js, _ = plan_paths(plan)
    fix = f"restore {js} from a known-good copy of the compiled plan state"
    text = read_required(js, "bad-state", fix, optional=True)
    if text is None:
        if required:
            raise missing_state(plan)
        return None
    try:
        st = json.loads(text)
        json.dumps(st, ensure_ascii=False).encode("utf-8")
    except (ValueError, RecursionError) as e:
        raise Refuse("bad-state", f"{js} is not valid JSON ({e})", fix)
    if problem := state_problem(st, md):
        raise Refuse("bad-state", f"{js}: {problem}", fix)
    return st


def code_owned(st, head):
    """File lines whose code-owned value differs from the state: [(line, text, command)]."""
    out, mask = [], fenced(head)
    for n, l in enumerate(header_of(head), 1):
        m = None if mask[n - 1] else STATUS_LINE.match(l)
        if m:
            if m[1] != st["status"]:
                out.append((n, l, "pipeline.py plan status"))
            if m[3] != st["base"]:
                out.append((n, l, "pipeline.py plan base"))
            if m[2] != st["branch"]:
                out.append((n, l, "pipeline.py build start"))
            break
    phases = {p["n"]: p for p in st["phases"]}
    for n, l in enumerate(head, 1):
        m = None if mask[n - 1] else PHASE_HEAD.match(l)
        if m and int(m[1]) in phases and phases[int(m[1])]["status"] != m[3]:
            out.append((n, l, "pipeline.py phase start / phase done"))
    return out


def render_head(st, head):
    out, slug = [], plan_slug(st)
    seen_status = False
    for l, in_fence in zip(head, fenced(head)):
        m = STATUS_LINE.match(l) if not seen_status and not in_fence else None
        if m:
            seen_status = True
            out.append(f"Status: {st['status']} · branch `{st['branch']}` · base `{st['base']}`")
            if not any(x.startswith("Rendered from `") for x in head):
                out.append(RENDERED.format(slug + ".json"))
            continue
        if l.startswith("Rendered from `") and not in_fence:
            l = RENDERED.format(slug + ".json")
        m = None if in_fence else PHASE_HEAD.match(l)
        ph = next((p for p in st["phases"] if m and p["n"] == int(m[1])), None)
        out.append(l[:m.start(3)] + ph["status"] + l[m.end(3):] if ph else l)
    return out


def plan_slug(st):
    return st["plan"][:-3]


def save(plan, st, head, tail):
    md, js, _ = plan_paths(plan)
    head = render_head(st, head)
    st["render_hash"] = head_hash(head)
    if st.get("lands"):
        tail = render_gate(plan, st)
        st["tail_hash"] = head_hash(tail)
    else:
        st.pop("tail_hash", None)
    for path, text in ((md, "\n".join(head + tail)), (js, json.dumps(st, indent=2, ensure_ascii=False) + "\n")):
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".pipeline-")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, path)
    sync_epic(plan_checkout(md), md, st)
    return head


def sync_epic(root, md, st):
    e = st.get("epic")
    if not e:
        return
    epic = os.path.join(root, e["path"])
    if not os.path.exists(epic):
        print(f"epic: {e['path']} is missing; row {e['row']} was not updated", file=sys.stderr)
        return
    cell = f"{st['status']} · `{os.path.relpath(os.path.realpath(md), os.path.realpath(root))}`"
    with open(epic + ".lock", "a") as lf:
        fcntl.flock(lf, fcntl.LOCK_EX)
        lines, i = epic_row(root, e["path"], e["row"])
        if i is None:
            return
        cut = lines[i].rstrip()
        if not cut.endswith("|"):
            return
        cut = cut[:-1].rstrip()
        new = cut[:cut.rfind("|") + 1] + f" {cell} |"
        if new != lines[i]:
            lines[i] = new
            fd, tmp = tempfile.mkstemp(dir=os.path.dirname(epic), prefix=".pipeline-")
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write("\n".join(lines))
            os.replace(tmp, epic)


def drift_diags(plan, st, head, tail=None):
    """What differs between the file and its last render, as Refuse diagnostics."""
    out = []
    if tail is not None and st.get("tail_hash") and head_hash(tail) != st["tail_hash"]:
        out.append(("drift", f"{plan}: `## Human gate` was edited by hand", "restore it; code draws it from the records, and `pipeline.py page` changes its guide and message"))
    if head_hash(head) == st.get("render_hash"):
        return out
    owned = code_owned(st, head)
    if owned:
        return out + [("drift", f"{plan}:{n}: `{t}` was edited by hand", f"restore it, or change it with `{c}`") for n, t, c in owned]
    return out + [("drift", f"{plan} differs from its last render", f"run `pipeline.py approve {plan}` to compile the edit")]


@contextlib.contextmanager
def writing(plan, edit_tail=None, *, skip_unchanged=False):
    """Lock the plan's state, refuse on drift, yield the state; saves and renders on exit.

    Call set_plan / set_phase inside; an exception leaves both files as they were.
    edit_tail(state, tail lines) -> tail lines rewrites the hand-written `## Human gate` on exit.
    """
    md = plan_paths(plan)[0]
    if not os.path.isdir(os.path.dirname(md)):
        read_plan(md)
    with locked(plan):
        head, tail = read_plan(md)
        st = load_state(plan, required=True)
        root = plan_checkout(md)
        checked_plan(md, head, root, check_references=False)
        if (epic := st.get("epic")) and os.path.lexists(os.path.join(root, epic["path"])):
            check_epic(root, epic["path"], epic["row"])
        diags = drift_diags(plan, st, head, tail)
        if diags:
            r = Refuse(*diags[0])
            r.diags = diags
            raise r
        before = digest(st) if skip_unchanged else None
        yield st
        if before is None or before != digest(st):
            save(plan, st, head, edit_tail(st, tail) if edit_tail else tail)


def record(plan, st, what, frm, to, note=None):
    """Append a history entry: when, what, from, to, the note and HEAD's SHA."""
    st["history"].append({"at": now(), "what": what, "from": frm, "to": to, "note": note, "sha": head_sha(plan_paths(plan)[0], tree_fact(plan, st))})


def set_plan(plan, st, *, status=None, branch=None, base=None, note=None):
    """Change the plan's code-owned fields; each change is one history entry."""
    for key, value in (("status", status), ("branch", branch), ("base", base)):
        if value is not None and value != st[key]:
            if key == "status" and value not in PLAN_STATUSES and not value.startswith("http"):
                raise Refuse("bad-status", f"{value!r} is not a plan status", "use one of: " + ", ".join(PLAN_STATUSES) + ", or a merge-request link")
            record(plan, st, key, st[key], value, note)
            st[key] = value


def set_phase(plan, st, n, status, note=None):
    """Change phase n's status; one history entry."""
    ph = next((p for p in st["phases"] if p["n"] == n), None)
    if ph is None:
        raise Refuse("no-phase", f"the plan has no phase {n}", "phases: " + ", ".join(str(p["n"]) for p in st["phases"]))
    if status not in PHASE_STATUSES:
        raise Refuse("bad-status", f"{status!r} is not a phase status", "use one of: " + ", ".join(PHASE_STATUSES))
    record(plan, st, f"phase {n}", ph["status"], status, note)
    ph["status"] = status


def ready_phases(st):
    """Phases still waiting whose Waits for are all done."""
    done = {p["n"] for p in st["phases"] if p["status"] == "done"}
    return [p["n"] for p in st["phases"] if p["status"] == "waiting" and set(p["waits"]) <= done]


# -- the run file: `<slug>.run.toml`, written before the plan

CHOICES = {("finish", "how"): ["merge-request", "ff-only", "no-ff"]}
RUN_SECTIONS = {
    "finish": {"how": "str", "target": "str", "delete_backups": "bool"},
    "checks": {"phase": "list", "full": "list", "build": "str", "dev": "str", "url": "str"},
    "isolation": {"port": "bool", "data_dir": "bool"},
}
RUN_OPTIONAL = {("checks", "build"), ("checks", "dev"), ("checks", "url"), ("isolation", "port"), ("isolation", "data_dir")}
PLACEHOLDER = re.compile(r"\{(port|data_dir)\}")
EXAMPLE = os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "run-file", "references", "example.run.toml")


def run_path(plan):
    return plan_paths(plan)[0][:-3] + ".run.toml"


def refuse_all(diags):
    r = Refuse(*diags[0])
    r.diags = diags
    return r


def type_ok(v, kind):
    if kind == "bool":
        return isinstance(v, bool)
    if kind == "str":
        return isinstance(v, str) and "\0" not in v
    return isinstance(v, list) and all(type_ok(x, "str") for x in v)


def single_line(value):
    return type_ok(value, "str") and bool(value.strip()) and len(value.splitlines()) == 1 and not value.endswith(("\n", "\r"))


def executor_diags(values):
    """Validate the fixed executor structure without restricting provider or model names."""
    out = []
    def bad(path, message):
        out.append(("executor-invalid", f"{path} {message}", "use [executors.\"PROVIDER\".primary] and secondary, each with model and optional effort"))
    if not isinstance(values, dict) or not values:
        bad("executors", "must be a nonempty table of provider profiles")
        return out
    for provider, profiles in values.items():
        path = "executors." + json.dumps(provider, ensure_ascii=False)
        if not single_line(provider):
            bad(path, "must name a nonblank single-line provider")
        if not isinstance(profiles, dict):
            bad(path, "must be a table")
            continue
        for tier in sorted(profiles.keys() - {"primary", "secondary"}):
            bad(f"{path}.{tier}", "is an unknown field")
        for tier in ("primary", "secondary"):
            profile = profiles.get(tier)
            here = f"{path}.{tier}"
            if not isinstance(profile, dict):
                bad(here, "must be a table")
                continue
            for key in sorted(profile.keys() - {"model", "effort"}):
                bad(f"{here}.{key}", "is an unknown field")
            for key in ("model", "effort"):
                if key == "model" or key in profile:
                    if not single_line(profile.get(key)):
                        bad(f"{here}.{key}", "must be a nonblank single-line string")
    return out


def agents_executors(tree):
    path = os.path.join(tree, "AGENTS.md")
    fix = f"add ## Executors with one fenced toml block of provider primary/secondary profiles to {path}"
    dups = []
    secs = sections(read_required(path, "executors-missing", fix).splitlines(), dups)
    body = "\n".join(secs.get("Executors", (0, []))[1])
    blocks = re.findall(r"(?ms)^```toml[ \t]*\n(.*?)^```[ \t]*$", body)
    if len(blocks) != 1 or any(name == "Executors" for _, name in dups):
        raise Refuse("executors-missing", f"{path} must have one ## Executors section with one fenced toml block", fix)
    try:
        values = tomllib.loads(blocks[0])
    except tomllib.TOMLDecodeError as e:
        raise Refuse("executors-bad-toml", f"{path} Executors is not valid TOML ({e})", fix)
    problems = [("executor-invalid", f"{path}: {key} is an unknown field in Executors", fix) for key in values if key != "executors"]
    problems += [(code, f"{path}: {message}", fix) for code, message, _ in executor_diags(values.get("executors"))]
    if problems:
        raise refuse_all(problems)
    return values["executors"], path


def executor_selection(plan, provider):
    if not single_line(provider):
        raise Refuse("bad-provider", "--provider must be a nonblank single-line identifier", "supply the current provider explicitly")
    st = load_state(plan) if plan else None
    if st and plan_approval(st):
        values, source = st.get("run", {}).get("executors", {}), "approved run snapshot"
    else:
        if st:
            tree = tree_of(plan, st)
        else:
            directory = os.path.dirname(plan_paths(plan)[0]) if plan else os.getcwd()
            while not os.path.isdir(directory):
                directory = os.path.dirname(directory)
            tree = plan_checkout(os.path.join(directory, "executor.md"))
        config = None
        if standalone_bundle() is not None:
            from runweld_release import project_root
            if project := project_root(tree):
                config = project / ".runweld/config.toml"
        if config is not None and os.path.lexists(config):
            _, settings = read_project_config(config)
            values, source = settings["executors"], str(config)
        else:
            values, source = agents_executors(tree)
    if provider not in values:
        if source == "approved run snapshot":
            fix = "add this provider's primary/secondary profiles to the run and obtain renewed human approval"
        elif source.endswith("/.runweld/config.toml"):
            fix = "run `runweld init --provider NAME` to add this provider's primary/secondary profiles"
        else:
            fix = "add this provider's primary/secondary profiles to AGENTS.md ## Executors"
        raise Refuse("executor-missing", f"executors.{json.dumps(provider, ensure_ascii=False)} is missing from {source}", fix)
    problems = executor_diags({provider: values[provider]})
    if problems:
        raise refuse_all(problems)
    return {"provider": provider, "source": source, **values[provider]}


def cmd_executor(plan, provider, as_json):
    selected = executor_selection(plan, provider)
    if as_json:
        print(json.dumps(selected, ensure_ascii=False))
    else:
        print(f"Provider: {provider}\nSource: {selected['source']}")
        for tier in ("primary", "secondary"):
            profile = selected[tier]
            print(f"{tier}: model = {json.dumps(profile['model'], ensure_ascii=False)}" +
                  (f", effort = {json.dumps(profile['effort'], ensure_ascii=False)}" if "effort" in profile else ""))
    return 0


def toml_statements(text):
    """Yield complete TOML statements, keeping multiline values intact."""
    try:
        tomllib.loads(text)
    except tomllib.TOMLDecodeError as e:
        raise Refuse("run-bad-toml", f"the copied run is not valid TOML ({e})", "fix the source run before copying it")
    statement = ""
    for line in text.splitlines(keepends=True):
        statement += line
        try:
            value = tomllib.loads(statement)
        except tomllib.TOMLDecodeError:
            continue
        yield statement, value
        statement = ""


def without_table(text, name, keep_header=False):
    """Remove a top-level TOML table and its subtables while preserving other text."""
    out, skipping, in_table = [], False, False
    for statement, value in toml_statements(text):
        if statement.lstrip().startswith("["):
            skipping, in_table = name in value, True
            if skipping and keep_header:
                out.append(statement)
        if not skipping and (in_table or name not in value):
            out.append(statement)
    return "".join(out)


def toml_value(value):
    if isinstance(value, dict):
        return "{ " + ", ".join(f"{toml_value(key)} = {toml_value(item)}" for key, item in value.items()) + " }"
    return json.dumps(value, ensure_ascii=False).replace("\x7f", r"\u007f")


def executor_toml(values):
    return "\n".join(f"[executors.{toml_value(provider)}.{tier}]\n" +
                     "\n".join(f"{key} = {toml_value(value)}" for key, value in profile.items()) + "\n"
                     for provider, profiles in values.items() for tier, profile in profiles.items())


def settings_toml(values):
    sections = []
    for name in ("workflow", "finish", "checks", "setup", "isolation", "executors", "run"):
        if name not in values:
            continue
        table = values[name]
        if name == "isolation":
            table = {key: enabled for key, enabled in table.items() if enabled}
            if not table:
                continue
        if name == "executors":
            sections.append(executor_toml(table))
        else:
            sections.append(f"[{name}]\n" + "".join(f"{key} = {toml_value(value)}\n" for key, value in table.items()))
    return "\n".join(sections)


def read_run_proposal(plan, *, draft=False):
    from runweld_release import ReleaseError, registered_task, release_pin, task_pin
    path = run_path(plan)
    try:
        task = registered_task(Path(plan_paths(plan)[0]))
        text, values = read_run_file(path, pending_finish=draft and task is not None)
        task_pin(release_pin(values, path), task, path)
    except ReleaseError as error:
        raise Refuse("run-release", str(error), "restore the release recorded at task entry") from None
    return text, values


def read_run(plan, *, draft=False):
    """-> (values, []) or (None, [(code, message, fix)]); the file is read as written."""
    try:
        _, values = read_run_proposal(plan, draft=draft)
    except Refuse as error:
        return None, error.diags
    return values, []


def read_run_file(path, *, pending_finish=False):
    fix = "repair the run file with `runweld run-file`, or create it with `pipeline.py run new`"
    text = read_required(path, "no-run-file", fix, newline="")
    try:
        values = tomllib.loads(text)
    except tomllib.TOMLDecodeError as e:
        raise Refuse("run-bad-toml", f"{path} is not valid TOML ({e})", "fix the TOML syntax in the run file")
    if problems := run_diags(values, pending_finish=pending_finish):
        raise refuse_all([(code, f"{message} ({path})", fix) for code, message, fix in problems])
    return text, values


def run_diags(v, *, project=False, pending_finish=False):
    sections = {k: v for k, v in RUN_SECTIONS.items() if not project or k != "finish"}
    allowed = (*sections, "executors", "setup") + (() if project else ("workflow", "run"))
    out = []
    for sec in v:
        if sec not in allowed:
            out.append(("run-unknown-section", f"[{sec}] is not allowed here", "use only " + ", ".join(f"[{name}]" for name in allowed)))
    if "workflow" in v:
        from runweld_release import ReleaseError, release_pin
        try:
            release_pin(v, "the run file")
        except ReleaseError:
            out.append(("run-bad-release", "[workflow] requires a version and its SHA-256 digest", "use the release recorded by runweld when it created the run"))
    if project or "executors" in v:
        out += executor_diags(v.get("executors"))
    if "setup" in v:
        setup = v["setup"]
        if not isinstance(setup, dict) or set(setup) != {"command"} or not single_line(setup["command"]):
            out.append(("run-bad-setup", "[setup] must contain only a nonblank single-line command",
                        'write `command = "your project setup command"` in [setup], or omit [setup]'))
    for sec, keys in sections.items():
        t = v.get(sec, {})
        if not isinstance(t, dict):
            out.append(("run-bad-type", f"[{sec}] must be a table", f"write [{sec}] as a section"))
            continue
        for k in t:
            if k not in keys:
                out.append(("run-unknown-key", f"[{sec}] {k} is not a key of the section", "use only: " + ", ".join(keys)))
        for k, kind in keys.items():
            if k not in t:
                if pending_finish and sec == "finish" and k in ("how", "target"):
                    continue
                if (sec, k) not in RUN_OPTIONAL:
                    out.append(("run-missing-key", f"[{sec}] {k} is missing", f"add `{k}` to [{sec}]"))
            elif not type_ok(t[k], kind):
                want = {"bool": "true or false", "str": "a string", "list": "a list of strings"}[kind]
                out.append(("run-bad-type", f"[{sec}] {k} must be {want}", f"write {k} as {want}"))
            elif (sec, k) in CHOICES and t[k] not in CHOICES[sec, k]:
                out.append(("run-bad-value", f"[{sec}] {k} = {t[k]!r} is not one of {', '.join(CHOICES[sec, k])}", f"use one of {', '.join(CHOICES[sec, k])}"))
    r = v.get("run", {})
    if not isinstance(r, dict):
        out.append(("run-bad-type", "[run] must be a table", "write [run] as a section"))
    else:
        for k, x in r.items():
            if not isinstance(x, (str, int, float, bool)):
                out.append(("run-bad-type", f"[run] {k} must be a string, number or boolean", f"write {k} as a plain value"))
    checks, resources = v.get("checks", {}), v.get("isolation", {})
    finish = v.get("finish", {})
    if not project and isinstance(finish, dict) and "target" in finish and not single_line(finish["target"]):
        out.append(("run-bad-target", "[finish] target must be a nonblank single-line branch", "set a target branch"))
    if isinstance(checks, dict) and isinstance(resources, dict):
        for k, x in checks.items():
            if project and type_ok(x, RUN_SECTIONS["checks"].get(k, "str")) and any(
                not s.strip() for s in (x if isinstance(x, list) else [x])
            ):
                out.append(("run-blank-check", f"[checks] {k} contains a blank entry",
                            "remove the blank entry or use a nonblank check"))
            for s in x if isinstance(x, list) else [x]:
                for ph in sorted(set(PLACEHOLDER.findall(s)) if isinstance(s, str) else []):
                    if resources.get(ph) is not True:
                        out.append(("run-bad-placeholder", f"[checks] {k} uses {{{ph}}}, but [isolation] {ph} is not true", f"set `{ph} = true` in [isolation], or drop the placeholder"))
    return out


def same(a, b):
    """Equal in value and type, so 1 and true differ."""
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(same(a[k], b[k]) for k in a)
    return type(a) is type(b) and a == b


def run_changes(old, new):
    """The (section, key) pairs whose value differs, sorted."""
    return sorted((s, k) for s in old.keys() | new.keys() for k in ((old.get(s) or {}).keys() | (new.get(s) or {}).keys())
                  if not same((old.get(s) or {}).get(k), (new.get(s) or {}).get(k)))


def run_drift(plan, st):
    """What differs between the proposed run and its frozen snapshot."""
    if "run" not in st or (st["status"] == "draft" and not plan_approval(st)):
        return []
    fix = "review the changed plan and run configuration, then renew human approval or restore the approved values"
    v, probs = read_run(plan)
    if v is None:
        return [("run-drift", f"{probs[0][1]}; the approved values stand", probs[0][2])]
    keys = [f"[{x}] {k}" for x, k in run_changes(st["run"], v)]
    return [("run-drift", f"the run file differs from the approved values ({', '.join(keys)}); the approved values stand", fix)] if keys else []


PORTS = range(4300, 4400)


def fill(values, alloc):
    """The run's values with {port} and {data_dir} in [checks] replaced by the allocation."""
    def sub(x):
        if isinstance(x, list):
            return [sub(i) for i in x]
        for k, v in (alloc or {}).items():
            x = x.replace("{" + k + "}", str(v))
        return x
    return {s: {k: sub(x) for k, x in t.items()} if s == "checks" else t for s, t in values.items()}


# A listener on ::1 does not block the IPv4 wildcard, so each family is probed on its own.
PROBES = [(socket.AF_INET, ""), (socket.AF_INET6, "::")]


def bindable(family, addr, port):
    """False only when the port is taken; a family the host cannot use (no IPv6) is skipped."""
    try:
        with socket.socket(family) as s:
            if family == socket.AF_INET6:
                s.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
            s.bind((addr, port))
    except OSError as e:
        return e.errno not in (errno.EADDRINUSE, errno.EACCES)
    return True


@contextlib.contextmanager
def port_lock(md):
    """Held from picking a port to saving it, so plans of one project never pick the same."""
    with contextlib.ExitStack() as locks:
        for d in plan_directories(plan_root(md), md):
            lf = locks.enter_context((d / ".ports.lock").open("a"))
            fcntl.flock(lf, fcntl.LOCK_EX)
        yield


def allocate(plan, md, st, have=None):
    """What [isolation] asks for and `have` lacks: {"port": n, "data_dir": path}."""
    resources, new = st.get("run", {}).get("isolation", {}), {}
    if resources.get("port") and "port" not in (have or {}):
        new["port"] = free_port(plan, md)
    if resources.get("data_dir") and "data_dir" not in (have or {}):
        if task := task_for(plan):
            new["data_dir"] = str(Path(task["artifacts"]) / "data")
        else:
            new["data_dir"] = os.path.join(os.path.dirname(os.path.abspath(md)), plan_slug(st) + ".data")
    return new


def ensure_allocation(plan, md, st):
    discovery = {}
    if task := task_for(plan):
        discovery = read_discovery(plan).get("alloc", {})
        if "data_dir" in discovery and Path(discovery["data_dir"]) != Path(task["artifacts"]) / "data":
            raise Refuse("discovery-allocation", f"{discovery_path(plan)} does not name the task's data directory",
                         "restore the recorded discovery allocation")
    previous = {**discovery, **st.get("alloc", {})}
    alloc = {**previous, **allocate(plan, md, st, previous)}
    if alloc:
        if "data_dir" in alloc:
            workflow_subdir(Path(alloc["data_dir"])).mkdir(exist_ok=True)
        st["alloc"] = alloc
    return alloc


def free_port(plan, md):
    """The first port of PORTS that nothing listens on and no live plan holds."""
    held = set()
    root = plan_root(md)
    for path in inventory(root, md):
        if str(path) != md:
            o = load_state(path)
            if o and o["status"] != "merged":
                held.add(o.get("alloc", {}).get("port"))
    for task in task_rows(Path(root)):
        path = task["plan"]
        if path != md and (load_state(path) or {}).get("status") != "merged":
            held.add(read_discovery(path).get("alloc", {}).get("port"))
    ports = PORTS
    for p in ports:
        if p in held:
            continue
        if all(bindable(fam, addr, p) for fam, addr in PROBES):
            return p
    raise Refuse("no-port", f"no free port in {ports.start}-{ports[-1]}", "stop a plan that holds one, or free a port")


def validate_project_config(path, values):
    if problems := run_diags(values, project=True):
        raise refuse_all([(code, f"{message} ({path})", fix) for code, message, fix in problems])


def read_project_config(path, *, optional=False):
    from runweld_release import read_data
    text = read_data(path, str)
    if text is None:
        if optional:
            return None, None
        raise Refuse("project-not-initialized", f"{path} is missing", "run `runweld init` in this project")
    try:
        values = tomllib.loads(text)
    except tomllib.TOMLDecodeError as error:
        raise Refuse("project-bad-toml", f"{path} is not valid TOML ({error})", "fix the TOML syntax") from None
    if "finish" in values:
        raise Refuse("project-finish", f"{path} contains a run-specific [finish] table", "remove [finish] from project config and choose the ending in each task")
    validate_project_config(path, values)
    return text, values


def init_provider():
    active = [provider for provider, detected in (("GPT", os.environ.get("CODEX_THREAD_ID")),
                                                   ("Claude", os.environ.get("CLAUDECODE") == "1")) if detected]
    return active[0] if len(active) == 1 else None


def init_answer(label, default=None):
    value = input(f"{label}" + (f" [{default}]" if default is not None else "") + ": ")
    return value if value.strip() else default


def init_optional(label, default):
    value = init_answer(label + " (optional; - for none)", default)
    return None if value == "-" else value


def init_checks(label, default):
    hint = " | ".join(default) or "none"
    first = init_answer(f"{label} (Enter keeps {hint}; - for none)")
    if first is None:
        return default
    if first == "-":
        return []
    commands = [first]
    while command := init_answer("Another command (Enter ends the list)"):
        commands.append(command)
    return commands


def init_bool(label, default):
    while True:
        value = init_answer(f"{label} (yes/no)", "yes" if default else "no").lower()
        if value in ("y", "yes", "n", "no"):
            return value in ("y", "yes")


def init_hints(project, text):
    _, lines = sections(text.splitlines()).get("Environment", (0, []))
    hints = {}
    for line, masked in zip(lines, fenced(lines)):
        if not masked and (match := re.match(r"(?:[-*]\s+)?\*\*([^*]+)\.\*\*\s+(.+)", line.strip())):
            hints[match[1].casefold()] = re.findall(r"`([^`]+)`", match[2])
    first = lambda key: next(iter(hints.get(key, ())), None)
    core = [commands[0] for key in ("build", "typecheck", "lint") if (commands := hints.get(key))]
    full = list(dict.fromkeys(core + hints.get("tests", [])[:1]))
    checks = {"phase": hints.get("phase checks", core), "full": hints.get("full checks", full)}
    dev = hints.get("dev server", [])
    for key, value in (("build", first("build")), ("dev", next(iter(dev), None)),
                       ("url", first("dev url") if "dev url" in hints else next(iter(dev[1:]), None))):
        if value:
            checks[key] = value
    setup_key = next((key for key in ("bootstrap", "worktree setup", "setup") if key in hints), None)
    script = project / "scripts/setup"
    setup = first(setup_key) if setup_key else ("scripts/setup" if script.is_file() and os.access(script, os.X_OK) else None)
    return {"checks": checks, **({"setup": {"command": setup}} if setup else {})}


def init_settings(project, hints, current, a, interactive):
    checks = hints.get("checks", {})
    fields = (
        ("checks", "phase", a.phase_check, "Phase checks", checks.get("phase", [])),
        ("checks", "full", a.full_check, "Full checks", checks.get("full", [])),
        ("checks", "build", a.build, None, checks.get("build")),
        ("isolation", "port", a.port, "Allocate a port per task", False),
        ("isolation", "data_dir", a.data_dir, "Allocate a data directory per task", False),
        ("checks", "dev", a.dev, "Dev command", checks.get("dev")),
        ("checks", "url", a.url, "Dev URL", checks.get("url")),
        ("setup", "command", a.setup, "Existing worktree bootstrap command (never run during init)", hints.get("setup", {}).get("command")),
    )
    settings = {"checks": {}}
    for sec, key, supplied, label, default in fields:
        if current is not None:
            value = current.get(sec, {}).get(key, False if sec == "isolation" else None)
            if supplied is not None and supplied != value:
                raise Refuse("project-default-exists", f"[{sec}] {key} is already configured",
                             f"edit {project / '.runweld/config.toml'} to change project defaults")
        elif supplied is not None:
            value = supplied
        elif interactive and label:
            if (sec == "checks" and (sec, key) in RUN_OPTIONAL) or sec == "setup":
                value = init_optional(label, default)
            elif isinstance(default, list):
                value = init_checks(label, default)
            elif isinstance(default, bool):
                value = init_bool(label, default)
            else:
                value = init_answer(label, default)
        else:
            value = default
        if value is not None and (sec != "isolation" or value):
            settings.setdefault(sec, {})[key] = value
    return settings


def init_agents(text):
    start, end = "<!-- runweld:begin -->", "<!-- runweld:end -->"
    nl = "\r\n" if "\r\n" in text else "\n"
    block = (nl * 2).join((start, "Start or resume work with `runweld next`.", end))
    markers = list(re.finditer(r"(?m)^<!-- runweld:(?:begin|end) -->(?=\r?$)", text))
    if not markers:
        gap = "" if not text or text.endswith(nl * 2) else nl if text.endswith(nl) else nl * 2
        return text + gap + block + nl
    if [marker.group() for marker in markers] != [start, end]:
        raise Refuse("project-agents-block", "AGENTS.md has mismatched Runweld block markers", "repair or remove the managed block markers")
    return text[:markers[0].start()] + block + text[markers[1].end():]


def add_init_profile(path, text, provider, pair):
    addition = executor_toml({provider: pair})
    normal = text + ("\n" if text.endswith("\n") else "\n\n") + addition
    try:
        tomllib.loads(normal)
        return normal
    except tomllib.TOMLDecodeError:
        pass
    cursor = 0
    for statement, value in toml_statements(text):
        prefix, _, rhs = statement.partition("=")
        if (not prefix.lstrip().startswith("[") and value.keys() == {"executors"} and rhs.lstrip().startswith("{")):
            start = cursor + len(prefix) + 1 + rhs.index("{") + 1
            candidate = text[:start] + f" {toml_value(provider)} = {toml_value(pair)}," + text[start:]
            try:
                if tomllib.loads(candidate)["executors"][provider] == pair:
                    return candidate
            except (tomllib.TOMLDecodeError, KeyError):
                pass
        cursor += len(statement)
    raise Refuse("project-executor-format", f"cannot add this provider without rewriting {path}",
                 "add the provider with primary and secondary profiles in the executors table and run runweld init again")


def init_ignore(project, text):
    def ignored(path):
        return git("check-ignore", "-q", "--no-index", "--", path, check=False, cwd=project).returncode == 0

    private = "/" + WORKFLOW_DIR + "/"
    rules = []
    if ignored(".runweld/config.toml") or ignored(".runweld/runweld.lock"):
        if ignored(".runweld/"):
            rules += ["!/.runweld/", "/.runweld/*"]
        rules += ["!/.runweld/config.toml", "!/.runweld/runweld.lock"]
    if rules or private not in text.splitlines() or not ignored(WORKFLOW_DIR + "/"):
        rules.append(private)
    if not rules:
        return text
    nl = "\r\n" if "\r\n" in text else "\n"
    return text + (nl if text and not text.endswith("\n") else "") + nl.join(rules) + nl


def write_init_text(path, before, after):
    from runweld_release import atomic_write
    if before != after:
        mode = stat.S_IMODE(path.stat().st_mode) if before is not None else 0o644
        atomic_write(path, after.encode("utf-8"), mode)


def cmd_init(bundle, a):
    from runweld_release import ReleaseError, project_root, read_data, read_lock, write_lock
    project = project_root(Path.cwd())
    if project is None:
        raise Refuse("no-repo", "the current directory is not in a Git project", "run `runweld init` in a Git checkout")
    common = Path(git("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=project).stdout.strip())
    with (common / "runweld-init.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        config, agents, ignore = (project / path for path in (".runweld/config.toml", "AGENTS.md", ".gitignore"))
        for path in (config.parent, config, agents, ignore):
            if path.is_symlink():
                raise Refuse("project-init-path", f"{path} is a symbolic link", "use a regular project file or directory")
        previous, current = read_project_config(config, optional=True)
        locked_release = read_lock(project, bundle.parent.parent)
        if locked_release is not None and locked_release != bundle.name:
            raise ReleaseError(f"{project} locks {locked_release}; run `runweld init` without a release override")
        agents_before, ignore_before = (read_data(path, str) for path in (agents, ignore))
        agents_after = init_agents(agents_before or "")
        ignore_after = init_ignore(project, ignore_before or "")

        interactive = sys.stdin.isatty() and not a.non_interactive
        defaults = init_hints(project, agents_before or "") if current is None else {}
        if current is None:
            print("Detected project defaults (commands are not run during init):\n" + settings_toml(defaults).rstrip())
        provider = a.provider if a.provider is not None else init_provider()
        if provider is None and interactive:
            provider = init_answer("Provider name (e.g. GPT or Claude)")
        if not single_line(provider):
            raise Refuse("bad-provider", "a nonblank single-line provider is required",
                         "pass --provider NAME or choose the provider in an interactive terminal")
        profiles = (current or {}).get("executors", {})
        try:
            hints, _ = agents_executors(project) if interactive and provider not in profiles else ({}, None)
        except Refuse:
            hints = {}
        pair = {}
        for tier in ("primary", "secondary"):
            model, effort = (getattr(a, f"{tier}_{key}") for key in ("model", "effort"))
            saved = profiles.get(provider, {}).get(tier)
            if saved is not None:
                if (model is not None and model != saved["model"]) or (effort is not None and effort != saved.get("effort")):
                    raise Refuse("executor-exists", f"executors.{toml_value(provider)}.{tier} already exists",
                                 f"edit {config} to change an existing profile")
                pair[tier] = saved
                continue
            if interactive:
                hint = hints.get(provider, {}).get(tier, {})
                if model is None:
                    model = init_answer(f"{provider} {tier} model", hint.get("model"))
                if effort is None:
                    effort = init_optional(f"{provider} {tier} effort", hint.get("effort"))
            pair[tier] = {"model": model}
            if effort is not None:
                pair[tier]["effort"] = effort
        settings = init_settings(project, defaults, current, a, interactive)
        settings["executors"] = {**profiles, provider: pair}
        validate_project_config(config, settings)
        updated = settings_toml(settings) if previous is None else previous
        if previous is not None and provider not in profiles:
            updated = add_init_profile(config, previous, provider, pair)

        for path, before in ((config, previous), (agents, agents_before), (ignore, ignore_before)):
            if read_data(path, str) != before:
                raise Refuse("project-init-changed", f"{path} changed during initialization", "rerun `runweld init`")
        config.parent.mkdir(exist_ok=True)
        write_init_text(config, previous, updated)
        write_init_text(agents, agents_before, agents_after)
        write_init_text(ignore, ignore_before, ignore_after)
        # Linked checkouts can be based on a commit made before the shared ignore entry.
        local_exclude = common / "info/exclude"
        excluded = read_data(local_exclude, str)
        private = f"/{WORKFLOW_DIR}/"
        if private not in (excluded or "").splitlines():
            if local_exclude.is_symlink():
                raise Refuse("project-init-path", f"{local_exclude} is a symbolic link", "add the private ignore entries there or use a regular file")
            workflow_subdir(local_exclude.parent).mkdir(exist_ok=True)
            write_init_text(local_exclude, excluded, (excluded or "").rstrip("\n") + "\n" + private + "\n")
        if locked_release is None:
            write_lock(project, bundle)
    print(f"Initialized {project} for {provider} on {bundle.name}. Run `runweld next` for the next step.")
    return 0


def snapshot_run(bundle, project, path, finish):
    from runweld_release import atomic_write
    src = project / ".runweld/config.toml"
    _, settings = read_project_config(src)
    version, digest = bundle.name.split("@")
    ending = {**finish, "delete_backups": finish.get("delete_backups", True)}
    values = {"workflow": {"version": version, "digest": digest}, "finish": ending, **settings, "run": {}}
    if problems := run_diags(values, pending_finish=True):
        raise refuse_all(problems)
    text = settings_toml(values)
    path.parent.mkdir(parents=True, exist_ok=True)
    # Write the complete file before publishing its name, without replacing a concurrent draft.
    with tempfile.TemporaryDirectory(dir=path.parent) as scratch:
        candidate = Path(scratch) / path.name
        atomic_write(candidate, text.encode("utf-8"), 0o600)
        try:
            os.link(candidate, path)
        except FileExistsError:
            raise Refuse("run-exists", f"{path} already exists", "edit it, or pick another plan name") from None
    return src


def task_lookup(project, name):
    from runweld_release import task_plan
    if not re.fullmatch(ID, name):
        raise Refuse("task-name", f"{name!r} is not a task ID", "use lowercase letters, numbers and hyphens")
    root = workflow_dir(project)
    for area in ("plans", "tasks"):
        workflow_subdir(root / area)
    if plan := task_plan(project, name):
        return task_for(plan, project)


def task_for(plan, project=None):
    from runweld_release import registered_task
    md = Path(plan_paths(plan)[0])
    root = workflow_dir(Path(project or plan_root(md)))
    plans = workflow_subdir(root / "plans")
    if (md.parent == plans or md.parent.parent == plans) and (value := registered_task(md)):
        tree = workflow_subdir(root / "trees") / md.stem
        artifacts = (workflow_subdir(root / "artifacts") / md.stem if md.parent == plans else md.parent / "artifacts")
        return {**value, "id": md.stem, "plan": str(md), "tree": str(tree), "artifacts": str(workflow_subdir(artifacts))}


def task_rows(project):
    from runweld_release import task_folders
    root = workflow_dir(project)
    tasks = workflow_subdir(root / "tasks")
    ids = {path.stem for path in tasks.glob("*.json") if re.fullmatch(ID, path.stem)}
    ids.update(name for name, folder in task_folders(workflow_subdir(root / "plans"))
               if os.path.lexists(folder / (name + ".task.json")))
    return [task_lookup(project, name) for name in sorted(ids)]


def ensure_task_tree(task, root):
    found = branch_tree(root, task["branch"])
    if not found or os.path.realpath(found) != task["tree"] or not os.path.isdir(found):
        path = shlex.quote(task["tree"])
        raise Refuse("task-tree", f"task {task['id']} owns {task['tree']} on {task['branch']}",
                     f"restore this checkout with `git worktree add {path} {task['branch']}`, or use the current checkout if it was moved back")


def discovery_path(plan):
    return Path(plan_paths(plan)[0]).with_suffix(".discovery.json")


def read_discovery(plan):
    from runweld_release import ReleaseError, read_data
    path = discovery_path(plan)
    data = read_data(path, json.loads)
    if data is None and not path.exists():
        return {"stages": {}}
    fix = "restore the saved copy"
    if problem := check_state_fields(data, {"stages": dict, "alloc?": {"port?": int, "data_dir?": str}}, str(path)):
        raise ReleaseError(f"{problem}; {fix}")
    fields = {"status": str, "questions": [str], **{key + "?": str for key in ("entered", "closed", "result", "reason", "command", "artifact")}}
    for stage, record in data["stages"].items():
        if problem := check_state_fields(record, fields, f"{path}.{stage}"):
            raise ReleaseError(f"{problem}; {fix}")
        if stage not in ("grill", "prototype", "reproduce") or record["status"] not in ("active", "done", "skipped"):
            raise ReleaseError(f"{path}.{stage} has an invalid discovery stage or status; {fix}")
        if stage == "reproduce" and (record["status"] == "skipped" or
                                     record["status"] == "done" and not all(record.get(key) for key in ("result", "command", "artifact"))):
            raise ReleaseError(f"{path}.{stage} has no red reproduction; {fix}")
    return data


def discovery_route(task):
    return ("reproduce",) if task.get("bug") else ("grill", "prototype")


def pending_discovery(task, stages):
    return next((stage for stage in discovery_route(task) if stages.get(stage, {}).get("status") not in ("done", "skipped")), None)


def discovery_in_use(task, stages):
    from runweld_release import DATED_TASK
    return bool(DATED_TASK.fullmatch(Path(task["plan"]).parent.name) or task.get("bug") or task.get("goal") or stages)


def discovery_artifact(task, value, *, red=False):
    artifacts = Path(task["artifacts"])
    try:
        path = Path(value).resolve()
    except (OSError, RuntimeError, ValueError) as error:
        raise Refuse("discovery-artifact", f"cannot resolve {value}: {error}", "use a path to the saved evidence") from None
    if not path.is_relative_to(artifacts) or (not path.is_dir() and not path.is_file()):
        raise Refuse("discovery-artifact", f"{value} is not an existing artifact in {artifacts}", "save the evidence under the task's artifacts")
    if red:
        read_required(path, "discovery-artifact", "save the failing test as a red patch under the task's artifacts")
    return str(path)


def require_discovery(task):
    stages = read_discovery(task["plan"])["stages"]
    if discovery_in_use(task, stages) and (stage := pending_discovery(task, stages)):
        label = "reproduction" if stage == "reproduce" else stage
        raise Refuse("discovery-incomplete", f"task {task['id']} still needs {label}", f"run `runweld next {task['id']}` for the current actions")
    if task.get("bug"):
        discovery_artifact(task, stages["reproduce"]["artifact"], red=True)


def on_reproduction_base(task):
    on_branch(task, task["tree"])
    if head_sha(task["plan"], task["tree"]) != task["base"]:
        raise Refuse("reproduction-base", f"the task worktree is no longer at {task['base']}",
                     "use the registered base for reproduction so the red evidence matches the plan")


def cmd_discovery(plan, a):
    from runweld_release import atomic_write
    if plan is None or (task := task_for(plan)) is None or not task["ready"]:
        raise Refuse("no-task", "discovery needs a registered task with a worktree", "run `runweld task start ID` or pass the plan path")
    plan = task["plan"]
    stage, event = a.stage, a.event
    if event == "skip" and stage in ("reproduce", "plan"):
        raise Refuse("required-stage", f"{stage} is required and cannot be skipped", f"run `runweld next {task['id']}` for the available actions")
    ensure_task_tree(task, plan_root(plan))
    setup_lock = task_setup_lock(task) if stage == "reproduce" and event == "done" else contextlib.nullcontext()
    with setup_lock, locked(plan):
        if load_state(plan):
            raise Refuse("discovery-closed", f"{plan} has already been compiled", "read the saved discovery with `runweld next`")
        data = read_discovery(plan)
        stages = data["stages"]
        current = pending_discovery(task, stages)
        if stage != current:
            raise Refuse("discovery-stage", f"{stage} is not the current stage (now {current or 'plan'})", f"run `runweld next {task['id']}`")
        if stage == "reproduce":
            on_reproduction_base(task)
        record = stages.get(stage)
        fields = {key: value for key, value in (("result", a.result), ("questions", a.questions),
                                               ("command", a.repro_command), ("artifact", a.artifact)) if value is not None}
        if a.clear_questions:
            fields["questions"] = []
        if ("command" in fields and stage != "reproduce" or a.reason is not None and event != "skip"
                or "artifact" in fields and stage not in ("prototype", "reproduce")
                or fields and event in ("start", "skip")):
            raise Refuse("discovery-input", "this event does not take those inputs", "use `runweld task stage --help`")
        if any(not item.strip() for value in fields.values() for item in (value if isinstance(value, list) else [value])):
            raise Refuse("discovery-input", "discovery inputs cannot be blank", "provide a result, question, command or artifact")
        if event == "start":
            if not record:
                record = {"entered": now(), "status": "active", "questions": []}
        elif event == "skip":
            if not (a.reason or "").strip():
                raise Refuse("skip-reason", f"skipping {stage} needs a reason", "pass --reason TEXT")
            record = {**(record or {"questions": []}), "status": "skipped", "reason": a.reason, "closed": now()}
        else:
            if not record:
                raise Refuse("discovery-not-started", f"{stage} has not been entered", f"run `runweld next {task['id']}` and start it first")
            if a.artifact is not None:
                fields["artifact"] = discovery_artifact(task, a.artifact, red=stage == "reproduce")
            if event == "save" and not fields:
                raise Refuse("discovery-input", "nothing to save", "pass a result, open questions or evidence")
            record.update(fields)
            if event == "done":
                if not record.get("result") or a.questions or record["questions"] and not a.result:
                    raise Refuse("discovery-result", f"{stage} needs its result and no open questions",
                                 "pass --result and resolve the questions before closing")
                if stage == "reproduce":
                    if not (record.get("command") and record.get("artifact")):
                        raise Refuse("discovery-result", "reproduction needs a repeatable red command and artifact",
                                     "pass --command SHELL and --artifact PATH")
                    discovery_artifact(task, record["artifact"], red=True)
                record.update(status="done", closed=now(), questions=[])
        if event != "start" or stage not in stages:
            stages[stage] = record
            atomic_write(discovery_path(plan), json.dumps(data, ensure_ascii=False).encode(), 0o600)
    stage = task_stage(task)
    return task_output({**task, "workflow": stage["workflow"], "discovery": stage["discovery"]}, a.json)


def discovery_actions(task, current, stages):
    plan, tree = task["plan"], task["tree"]
    owner = "Human and planner" if current == "grill" else "Planner"
    guide = "bug" if current == "reproduce" else current
    guide_action = work_action(owner, f"Read the {guide} instructions for this task.", "planner", current,
                               cwd=tree, instructions=[[*cli_argv(plan), guide, "--plan", plan]])
    if current == "plan":
        actions = [guide_action]
        if Path(plan).is_file():
            actions += [run_action(plan, owner, "Check the draft against the registered base.", "spec check"),
                        run_action(plan, owner, "Validate the draft without approving it.", "approve")]
        return actions
    def command(event, action, **inputs):
        return workflow_action(owner, "run", action, cwd=tree, argv=[*cli_argv(plan), guide, event, plan], **inputs)
    if current not in stages:
        actions = [guide_action, command("start", f"Enter {current} and keep progress for later.")]
    else:
        actions = [guide_action]
        if current == "reproduce":
            actions += setup_actions(task)
        if questions := stages[current]["questions"]:
            actions.append(workflow_action("Human", "ask", f"Resolve the saved questions for {current}.", input="discovery-questions", questions=questions))
        result = {"result": "--result TEXT"}
        if current in ("prototype", "reproduce"):
            result["artifact"] = "--artifact PATH"
        if current == "reproduce":
            result["command"] = "--command SHELL"
        actions += [command("save", "Save work so far and the current open questions.",
                            options={**result, "questions": "--question TEXT (repeatable) or --clear-questions"}),
                    command("done", f"Record the {current} result and go to the next stage.", options=result)]
    if current != "reproduce":
        actions.append(command("skip", f"Skip the optional {current} stage and save why.", options={"reason": "--reason TEXT"}))
    return actions


def task_stage(task, *, workflow=True):
    plan = task["plan"]
    row = {"plan": task["id"], "path": plan, "status": "planning", "branch": task["branch"],
           "base": task["base"], "tree": task["tree"], "ready": [], "release": task.get("release") or plan_release(plan)}
    if not workflow:
        return row
    if task["ready"]:
        data = read_discovery(plan)
        stages = data["stages"]
        current = pending_discovery(task, stages) or "plan"
        actions = discovery_actions(task, current, stages)
        states = {stage: value["status"] for stage, value in stages.items() if stage != "reproduce"}
        if task.get("bug"):
            states = dict.fromkeys(("grill", "prototype"), "not applicable")
        view = workflow_view(plan, "plan" if current == "reproduce" else current, actions, states)
        return {**row, "discovery": stages, "workflow": {**view, "stage": current}}
    else:
        step = workflow_action("Planner", "run", f"Retry `runweld task start {task['id']}` to finish task entry.",
                               cwd=plan_root(plan), argv=[*cli_argv(plan), "task", "start", task["id"]])
    return {**row, "workflow": workflow_view(plan, "grill", [step])}


def artifact_path(root, area):
    if area and not re.fullmatch(ID, area):
        raise Refuse("artifact-name", f"{area!r} is not an artifact directory name", "use lowercase letters, numbers and hyphens")
    return root / area if area else root


def cmd_path(area):
    from runweld_release import project_root
    project = project_root(Path.cwd())
    if project is None:
        raise Refuse("no-repo", "not inside a Git project", "run this command in the project")
    print(artifact_path(workflow_dir(project), area))
    return 0


def task_output(row, as_json):
    if as_json:
        print(json.dumps(row, ensure_ascii=False))
    else:
        print(f"Task: {row['id']} · branch `{row['branch']}` · base `{row['base']}`")
        print(f"Tree: {row['tree']}\nPlan: {row['plan']}\nArtifacts: {row['artifacts']}")
        if row.get("goal"):
            print(f"Goal: {row['goal']}")
        show_discovery(row.get("discovery", {}))
        if workflow := row.get("workflow"):
            show_workflow(workflow)
    return 0


def cmd_task(bundle, a):
    from runweld_release import ReleaseError, atomic_write, project_root, read_lock
    project = project_root(Path.cwd())
    if project is None:
        raise Refuse("no-repo", "not inside a Git project", "run this command in the project")
    name = a.id
    row = task_lookup(project, name)
    if a.command != "start":
        if row is None:
            raise Refuse("no-task", f"there is no task {name}", "use `runweld task start ID` for new work or `runweld status` to find existing work")
        if a.command == "path":
            print(artifact_path(Path(row["artifacts"]), a.area))
            return 0
        if Path(row["plan"]).is_file():
            return cmd_status(row["plan"], a.json, os.getcwd(), provider=a.provider)
        if row["ready"]:
            ensure_task_tree(row, project)
        stage = task_stage(row)
        return task_output({**row, **{k: stage[k] for k in ("workflow", "release", "discovery") if k in stage}}, a.json)

    root = workflow_dir(project)
    tasks = workflow_subdir(root / "tasks")
    plans = workflow_subdir(root / "plans")
    tree = workflow_subdir(root / "trees") / name
    tasks.mkdir(parents=True, exist_ok=True)
    # Older releases take the same lock when reserving an ID.
    with (tasks / ".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        row = task_lookup(project, name)
        r = lambda *args: git(*args, cwd=project, check=False)
        branch = "runweld/" + name
        branch_tip = r("rev-parse", "--verify", "-q", f"refs/heads/{branch}").stdout.strip()
        finish = {key: value for key, value in (("how", a.finish_how), ("target", a.finish_target),
                                                 ("delete_backups", a.delete_backups)) if value is not None}
        target = finish.get("target")
        if target is not None and (not single_line(target) or target.startswith("-") or r("check-ref-format", "refs/heads/" + target).returncode):
            raise Refuse("run-bad-target", "invalid finish target branch", "choose a Git branch name")
        if row is None:
            if read_lock(project, bundle.parent.parent) != bundle.name:
                raise ReleaseError(f"{project} does not lock {bundle.name}; run `runweld init` or use `runweld` without a release override")
            read_project_config(project / ".runweld/config.toml")
            base = a.base or "HEAD"
            commit = r("rev-parse", "--verify", "-q", "--end-of-options", f"{base}^{{commit}}")
            if commit.returncode:
                raise Refuse("unknown-ref", f"{base} is not a commit", "name a project base with --base")
            folder = plans / f"{datetime.date.today()}-{name}"
            if branch_tip or any(os.path.lexists(p) for p in (folder, tree, plans / (name + ".run.toml"),
                        workflow_subdir(root / "artifacts") / name)) or any(p.stem == name for p in inventory(project)):
                raise Refuse("task-collision", f"task {name} conflicts with an existing plan, branch, or path", "choose a different task ID")
            if a.goal is not None and not a.goal.strip():
                raise Refuse("task-goal", "the task goal cannot be blank", "pass --goal with the requested outcome")
            reservation = {"base": commit.stdout.strip(), "branch": branch, "ready": False, "release": bundle.name, "finish": finish}
            if a.goal is not None:
                reservation["goal"] = a.goal
            if a.bug:
                reservation["bug"] = True
            plans.mkdir(exist_ok=True)
            with tempfile.TemporaryDirectory(prefix=".task-", dir=plans) as scratch:
                atomic_write(Path(scratch) / (name + ".task.json"), json.dumps(reservation).encode(), 0o600)
                Path(scratch).rename(folder)
            row = task_lookup(project, name)
        plan = Path(row["plan"])
        artifacts = Path(row["artifacts"])
        record_path = tasks / (name + ".json") if plan.parent == plans else plan.with_suffix(".task.json")
        run_file = Path(run_path(plan))
        if ((a.goal is not None and a.goal != row.get("goal")) or (a.bug and not row.get("bug"))):
            raise Refuse("task-intent", f"task {name} is already registered with a different intent", "omit intent flags when resuming an existing task")
        if (release := plan_release(plan) or read_lock(project, bundle.parent.parent)) != bundle.name:
            raise ReleaseError(f"this run selects {release}, not {bundle.name}; use `runweld` without a release override")
        if a.base and r("rev-parse", "--verify", "-q", "--end-of-options", f"{a.base}^{{commit}}").stdout.strip() != row["base"]:
            raise Refuse("task-base", f"task {name} already started at {row['base']}", "omit --base to resume this task")
        if "finish" in row and not run_file.exists():
            if any(row["finish"].get(key) != value for key, value in finish.items()):
                raise Refuse("task-finish", "the interrupted task has a reserved ending", "retry without finish flags, then edit the run file")
            finish = row["finish"]
        if finish and run_file.exists():
            from runweld_release import read_data
            recorded = read_data(run_file, tomllib.loads).get("finish", {})
            if not isinstance(recorded, dict) or any(recorded.get(key) != value for key, value in finish.items()):
                raise Refuse("task-finish", "this task already has a run file", f"edit [finish] in {run_file} and approve the run")
        if row["ready"]:
            state = load_state(plan)
            if not state or state["status"] != "merged":
                ensure_task_tree(row, project)
        else:
            if not os.path.lexists(run_file):
                snapshot_run(bundle, project, run_file, finish)
            plan_dir = plan.parent
            plan_dir.mkdir(parents=True, exist_ok=True)
            tree.parent.mkdir(parents=True, exist_ok=True)
            workflow_subdir(artifacts).mkdir(parents=True, exist_ok=True)
            if branch_tree(project, branch):
                ensure_task_tree(row, project)
            elif os.path.lexists(tree) or (branch_tip and branch_tip != row["base"]):
                raise Refuse("task-collision", f"the reserved tree or branch for task {name} changed", "move the conflicting path aside and retry")
            else:
                add = r("worktree", "add", *(("-b", branch, str(tree), row["base"]) if not branch_tip else (str(tree), branch)))
                if add.returncode:
                    raise Refuse("task-worktree", add.stderr.strip(), f"fix the Git error and retry `runweld task start {name}`")
            row.pop("finish", None)
            row.update(ready=True, release=bundle.name)
            atomic_write(record_path, json.dumps({k: row[k] for k in ("base", "ready", "branch", "release", "goal", "bug") if k in row}).encode(), 0o600)
    if plan.is_file():
        return cmd_status(str(plan), a.json, os.getcwd())
    stage = task_stage(row)
    return task_output({**row, **{k: stage[k] for k in ("workflow", "release", "discovery") if k in stage}}, a.json)


def task_env(task, project, alloc):
    values = {"RUNWELD_SOURCE_CHECKOUT": project, "RUNWELD_TASK_PATH": task["tree"], "RUNWELD_PLAN": task["plan"],
              "RUNWELD_WORKFLOW": workflow_dir(project), "RUNWELD_ARTIFACTS": task["artifacts"],
              "RUNWELD_PORT": alloc.get("port"), "RUNWELD_DATA_DIR": alloc.get("data_dir")}
    return {**{k: v for k, v in os.environ.items() if k not in values},
            **{k: str(v) for k, v in values.items() if v is not None}}


@contextlib.contextmanager
def task_setup_lock(task):
    artifacts = workflow_subdir(Path(task["artifacts"]))
    artifacts.mkdir(exist_ok=True, parents=True)
    with (artifacts / ".setup.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield lock


def read_setup(plan, task, *, reproduction):
    if reproduction:
        data = read_discovery(plan)
        if (not task.get("bug") or data["stages"].get("reproduce", {}).get("status") != "active"
                or load_state(plan) is not None):
            raise Refuse("task-setup-status", f"task {task['id']} has no active pre-plan reproduction",
                         f"run `runweld next {task['id']}` to enter reproduction or use approved task setup")
        run, problems = read_run(plan, draft=True)
        if problems:
            raise refuse_all(problems)
        return run, data
    st = load_state(plan)
    if st is None or st["status"] not in ("approved", *LIVE):
        raise Refuse("task-setup-status", f"task {task['id']} does not have an approved or active plan",
                     "prepare the environment after approval or use --reproduction for an active bug investigation")
    require_consent(plan, st)
    return st["run"], st


def setup_effects(task, run, alloc):
    resources = run.get("isolation", {})
    return {"command": run.get("setup", {}).get("command"), "cwd": task["tree"],
            "data_dir": alloc.get("data_dir") or (str(Path(task["artifacts"]) / "data") if resources.get("data_dir") else None),
            "port": alloc.get("port") or ("allocate a task-local port" if resources.get("port") else None)}


def show_setup(effects):
    value = effects["command"]
    print(f"Setup in {effects['cwd']}: {value if value else 'no configured command'}", flush=True)
    for key in ("port", "data_dir"):
        if effects[key] is not None:
            print(f"  {key.replace('_', ' ')}: {effects[key]}", flush=True)
    if effects.get("recorded"):
        print("  This command and these resources are already recorded as prepared.")


def setup_actions(task):
    from runweld_release import read_data
    plan, tree = task["plan"], task["tree"]
    argv = [*cli_argv(plan), "task", "setup", plan, "--reproduction"]
    try:
        run, data = read_setup(plan, task, reproduction=True)
    except Refuse as error:
        return [workflow_action("Planner", "ask", "Repair the run configuration before preparing reproduction.",
                                input="run-config", evidence=[f"{message} — fix: {fix}" for _, message, fix in error.diags])]
    alloc = data.get("alloc", {})
    effects = setup_effects(task, run, alloc)
    if effects["command"] and read_data(Path(task["artifacts"]) / ".setup", str) == digest([effects["command"], alloc]):
        effects["recorded"] = True
    return [workflow_action("Planner", "run", "Preview the configured reproduction setup without running it.",
                            cwd=tree, argv=[*argv, "--preview"], effects=effects),
            workflow_action("Planner", "run", "Prepare the task worktree if reproduction needs this setup.", cwd=tree, argv=argv)]


def setup_paths(tree, *, ignored=False):
    args = ("--ignored", "--exclude-standard") if ignored else ("--cached",)
    result = subprocess.run(["git", "ls-files", "-z", "--others", *args], cwd=tree, capture_output=True)
    if result.returncode == 0:
        return set(map(os.fsdecode, filter(None, result.stdout.split(b"\0"))))
    return None


def setup_identity(tree, name):
    path = Path(tree) / name
    try:
        if not path.is_relative_to(tree) or path.parent.resolve() != path.parent:
            return None
        info = path.lstat()
    except (OSError, RuntimeError):
        return None
    if stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode):
        return [info.st_dev, info.st_ino, info.st_ctime_ns, info.st_mtime_ns, info.st_size, info.st_mode]
    return None


def setup_ownership(task):
    from runweld_release import ReleaseError, read_data
    path = Path(task["artifacts"]) / ".setup-outputs.json"
    outputs = read_data(path, json.loads)
    if outputs is None and not os.path.lexists(path):
        return path, {}
    if not isinstance(outputs, dict) or any(not isinstance(identity, list) or len(identity) != 6
                                            or not all(type(part) is int for part in identity) for identity in outputs.values()):
        raise ReleaseError(f"{path} has invalid setup ownership records")
    return path, outputs


def cmd_task_setup(plan, *, implicit=False, reproduction=False, preview=False):
    from runweld_release import atomic_write, read_data
    md = plan_paths(plan)[0]
    root = plan_root(md)
    task = task_for(plan, root)
    if task is None:
        if implicit:
            return 0
        raise Refuse("no-task", f"{md} is not a registered task plan", "start the task with `runweld task start ID`")
    ensure_task_tree(task, root)
    if preview:
        run, data = read_setup(plan, task, reproduction=reproduction)
        show_setup(setup_effects(task, run, data.get("alloc", {})))
        return 0
    with task_setup_lock(task) as lock:
        tree = task["tree"]
        if reproduction:
            with port_lock(md), locked(plan):
                on_reproduction_base(task)
                run, data = read_setup(plan, task, reproduction=True)
                resources = {"run": run, "alloc": data.get("alloc", {})}
                alloc = ensure_allocation(plan, md, resources)
                data["alloc"] = alloc
                atomic_write(discovery_path(plan), json.dumps(data, ensure_ascii=False).encode(), 0o600)
        else:
            with port_lock(md), writing(plan) as st:
                run, _ = read_setup(plan, task, reproduction=False)
                on_branch(st, tree)
                alloc = ensure_allocation(plan, md, st)
        command = run.get("setup", {}).get("command")
        if not command:
            return 0
        stamp = Path(task["artifacts"]) / ".setup"
        binding = digest([command, alloc])
        if read_data(stamp, str) == binding:
            return 0
        ownership, previous = setup_ownership(task)
        existing = setup_paths(tree)
        still_owned = {name for name, identity in previous.items() if identity == setup_identity(tree, name)}
        show_setup(setup_effects(task, run, alloc))
        result = subprocess.run(command, cwd=tree, shell=True, env=task_env(task, root, alloc),
                                pass_fds=(lock.fileno(),))
        if existing is not None and (ignored := setup_paths(tree, ignored=True)) is not None:
            # Cleanup owns unchanged records, not an entire ignored directory.
            outputs = {name: identity for name in ignored if name in still_owned or name not in existing
                       if (identity := setup_identity(tree, name)) is not None}
            atomic_write(ownership, json.dumps(outputs).encode(), 0o600)
        if result.returncode:
            suffix = " --reproduction" if reproduction else ""
            raise Refuse("task-setup-failed", f"setup exited {result.returncode} in {tree}",
                         f"fix setup and retry `runweld task setup {shlex.quote(md)}{suffix}` in the same task")
        atomic_write(stamp, binding.encode(), 0o600)
    return 0


def cmd_run(command, plan, as_json):
    path = run_path(plan)
    if command == "new":
        if os.path.lexists(path):
            raise Refuse("run-exists", f"{path} already exists", "edit it, or pick another plan name")
        d = os.path.dirname(path)
        if bundle := standalone_bundle():
            project = Path(plan_root(plan_paths(plan)[0]))
            task = task_for(plan, project)
            if task is None or task["ready"]:
                raise Refuse("task-required", "standalone runs are created at task entry", "use `runweld task start ID`; restore an existing task's run file from its saved copy")
            src = snapshot_run(bundle, project, Path(path), task.get("finish", {}))
            print(f"run new: {path} (snapshot from {src})")
            return 0
        runs = [os.path.join(d, f) for f in os.listdir(d) if f.endswith(".run.toml")] if os.path.isdir(d) else []
        src = max(runs, key=lambda name: os.lstat(name).st_mtime) if runs else os.path.normpath(EXAMPLE)
        text, _ = read_run_file(src)
        if not runs:
            text = without_table(text, "run", keep_header=True)
        directory = d
        while not os.path.isdir(directory):
            directory = os.path.dirname(directory)
        st = load_state(plan)
        values, _ = agents_executors(tree_of(plan, st) if st else plan_checkout(os.path.join(directory, "executor.md")))
        text = without_table(text, "executors")
        snapshot = executor_toml(values) + "\n"
        out = []
        for statement, value in toml_statements(text):
            if snapshot and statement.lstrip().startswith("[") and "run" in value:
                out.append(snapshot)
                snapshot = ""
            out.append(statement)
        text = "".join(out).rstrip() + "\n" + ("\n" + snapshot if snapshot else "")
        os.makedirs(d, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        print(f"run new: {path} (copied from {src})")
        return 0
    v, probs = read_run(plan, draft=command == "show")
    if command == "check":
        if probs:
            raise refuse_all(probs)
        return 0
    st = load_state(plan)
    if st is not None and "run" in st and (plan_approval(st) or st["status"] != "draft"):
        v, drift = fill(st["run"], st.get("alloc")), run_drift(plan, st)
    elif probs:
        raise refuse_all(probs)
    else:
        drift = []
    if as_json:
        print(json.dumps({"run": v, "approved": bool(plan_approval(st or {})), "alloc": (st or {}).get("alloc"), "drift": [f"{m} — fix: {f}" for _, m, f in drift]}, ensure_ascii=False))
        return 0
    for sec, t in v.items():
        if sec == "executors":
            print(executor_toml(t))
            continue
        print(f"[{sec}]")
        for k, x in t.items():
            print(f"{k} = {json.dumps(x, ensure_ascii=False)}")
    for k, label in (("port", "Port"), ("data_dir", "Data dir")):
        if k in ((st or {}).get("alloc") or {}):
            print(f"{label}: {st['alloc'][k]}")
    for _, m, f in drift:
        print(f"Drift: {m} — fix: {f}")
    return 0


# -- commands

def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def planning_lines(head):
    lines = []
    for line, masked in zip(head, fenced(head)):
        if not masked and (STATUS_LINE.match(line) or line.startswith("Rendered from `")):
            continue
        m = None if masked else PHASE_HEAD.match(line)
        lines.append(line[:m.start(3)] + "waiting" + line[m.end(3):] if m else line)
    return lines


def planning_digest(plan):
    return digest(planning_lines(read_plan(plan_paths(plan)[0])[0]))


def plan_approval(st):
    approvals = st.get("approvals", {})
    return approvals.get("plan") or approvals.get("run")


def acceptance_authority(st):
    approvals = st["approvals"]
    return approvals.get("plan") or approvals["summary"]


def approval_revision(st, lines, run):
    return digest([st["plan"], lines, run])


def approval_argv(plan, revision):
    return [*cli_argv(plan), "plan", "approve", plan_paths(plan)[0], "--revision", revision]


def review_diff(old, new, label):
    return list(difflib.unified_diff(old, new, "approved " + label, "proposed " + label, lineterm=""))


def cmd_plan_review(plan, as_json):
    md = plan_paths(plan)[0]
    head, tail = read_plan(md)
    st = load_state(plan, required=True)
    text, run = read_run_proposal(plan)
    lines = planning_lines(head)
    revision = approval_revision(st, lines, run)
    diff = []
    if previous := st.get("approvals", {}).get("plan"):
        diff += review_diff(previous["planning"], lines, "plan")
    if plan_approval(st) and "run" in st:
        settings = lambda values: json.dumps(values, sort_keys=True, indent=2, ensure_ascii=False).splitlines()
        diff += review_diff(settings(st["run"]), settings(run), "run configuration")
    validation = drift_diags(plan, st, head, tail)
    consent = consent_diags(plan, st, head=head, values=run)
    result = {"plan_path": md, "plan": "\n".join(lines), "run_path": run_path(plan), "run_toml": text, "run": run,
              "branch": st["branch"], "base": st["base"], "revision": revision, "diff": diff,
              "approval": acceptance_authority(st) if not consent else st.get("approvals", {}).get("plan"),
              "current": not (consent or validation), "diagnostics": [dict(code=c, message=m, fix=f) for c, m, f in validation + consent],
              "approval_command": {"cwd": plan_root(md), "argv": approval_argv(plan, revision),
                                   "options": {"approver": "--by NAME", "words": "--words APPROVAL"}} if not validation else None}
    if as_json:
        print(json.dumps(result, ensure_ascii=False))
        return 0
    print(f"Plan: {md}\nBranch: {st['branch']} · Base: {st['base']}\n"
          f"Planning content (live progress is separate)\n\n{result['plan'].rstrip()}")
    print(f"\nRun configuration: {result['run_path']}\n\n{text.rstrip()}")
    if diff:
        print("\nChanges since approval:\n" + "\n".join(diff))
    for code, message, fix in validation:
        print(f"\n{code}: {message} — fix: {fix}")
    for code, message, _ in consent:
        print(f"\n{code}: {message}")
    print(f"\nRevision: {revision}")
    if result["current"]:
        print(f"Current approval by {result['approval']['by']}.")
    elif result["approval_command"]:
        print("After explicit human approval, record it with:\n  " +
              shlex.join(result["approval_command"]["argv"]) + " --by NAME --words APPROVAL")
    return 0


# Default_Ignorable_Code_Point from https://www.unicode.org/Public/18.0.0/ucd/DerivedCoreProperties.txt
# See references/unicode-license.txt.
DEFAULT_IGNORABLE = re.compile(
    "[\u00ad\u034f\u061c\u115f-\u1160\u17b4-\u17b5\u180b-\u180f"
    "\u200b-\u200f\u202a-\u202e\u2060-\u206f\u3164\ufe00-\ufe0f\ufeff"
    "\uffa0\ufff0-\ufff8\U0001bca0-\U0001bca3\U0001d173-\U0001d17a"
    "\U000e0000-\U000e0fff]"
)


def summary_destinations(text):
    from _marko.inline import CodeSpan, Image, Link, Literal, RawText, unescape_text
    from _marko.parser import Parser

    def has_visible_label(link):
        pending = list(link.children)
        while pending:
            node = pending.pop()
            if isinstance(node, Image) and node.dest.strip():
                return True
            if isinstance(node, (RawText, Literal, CodeSpan)):
                label = unescape_text(node.children) if isinstance(node, RawText) else node.children
                label = DEFAULT_IGNORABLE.sub("", label)
                if any(char.isprintable() and not char.isspace() for char in label):
                    return True
            elif isinstance(node.children, list):
                pending.extend(node.children)
        return False

    try:
        document = Parser().parse(text)
    except RecursionError:
        return
    pending = [document]
    while pending:
        node = pending.pop()
        if isinstance(node, Link):
            if has_visible_label(node):
                yield node.dest
        elif not isinstance(node, Image) and isinstance(node.children, list):
            pending.extend(reversed(node.children))


def read_summary(plan, path):
    fix = "write and present a summary of at most 350 words with a visible link such as `[Plan](<path to plan.md>)`"
    source = path
    text = read_required(source, "no-summary", fix)
    expected = os.path.realpath(plan_paths(plan)[0])
    if len(text.split()) > 350:
        raise Refuse("bad-summary", f"{source} must link this plan and contain at most 350 words", fix)
    for target in summary_destinations(markdown_newlines(text)):
        if re.match(r"(?:[A-Za-z][A-Za-z0-9+.-]*:|//)", target):
            continue
        local = unquote(re.split(r"[?#]", target, maxsplit=1)[0])
        if local and "\0" not in local:
            # Relative links start at the recorded summary pathname, not its symlink target.
            try:
                if os.path.realpath(os.path.join(os.path.dirname(path), local), strict=True) == expected:
                    return text
            except OSError:
                continue
    raise Refuse("bad-summary", f"{source} must link this plan and contain at most 350 words", fix)


def consent_diags(plan, st, *, head=None, values=None):
    approvals = st.get("approvals", {})
    run = approvals.get("run")
    review = shlex.join([*cli_argv(plan), "plan", "review", plan_paths(plan)[0]])
    fix = f"run `{review}` and obtain current human approval"
    if values is None:
        values, problems = read_run(plan)
        if problems:
            if not plan_approval(st) and "run" not in st and not os.path.lexists(run_path(plan)):
                return [("plan-unapproved", problems[0][1], f"{problems[0][2]}, then {fix}")]
            return problems
    if approval := approvals.get("plan"):
        if "run" not in st or approval["run"] != digest(st["run"]):
            return [("approval-snapshot", f"{plan_paths(plan)[1]} has no matching approved run snapshot", "restore the saved state")]
        if head is None:
            head, _ = read_plan(plan_paths(plan)[0])
        lines = planning_lines(head)
        if approval["revision"] != approval_revision(st, approval["planning"], st["run"]):
            return [("approval-snapshot", f"{plan_paths(plan)[1]} has no matching approved plan snapshot", "restore the saved state")]
        drift = []
        if lines != approval["planning"]:
            drift.append(("plan-stale", "the plan content, including its Done or Spec criteria, differs from its approval", fix))
        if digest(values) != approval["run"]:
            keys = ", ".join(f"[{section}] {key}" for section, key in run_changes(st["run"], values))
            drift.append(("run-stale", f"the run configuration differs from its approval ({keys or 'section structure changed'})", fix))
        return drift
    if not run:
        return [("plan-unapproved", "the proposed plan and run configuration have no human approval", fix)]
    if "run" not in st:
        return [("run-stale", f"{plan_paths(plan)[1]} has no approved run snapshot", fix)]
    if digest(values) != run["digest"] or digest(st["run"]) != run["digest"]:
        return [("run-stale", f"{run_path(plan)} differs from its approval", fix)]
    summary = approvals.get("summary")
    if not summary:
        return [("plan-unapproved", "the legacy run-only approval does not cover the complete plan", fix)]
    try:
        text = read_summary(plan, summary["file"])
    except Refuse as error:
        return error.diags
    if summary["planning"] != planning_digest(plan) or summary["run"] != run["digest"] or digest(text) != summary["digest"]:
        return [("plan-stale", f"the legacy approval's plan, Spec or linked summary ({summary['file']}) changed", fix)]
    return []


def require_consent(plan, st, *, head=None):
    if problems := consent_diags(plan, st, head=head):
        raise refuse_all(problems)


def approval_words(a):
    if not single_line(a.by) or not a.words.strip():
        raise Refuse("empty-approval", "approval needs a single-line human name and nonblank words", "pass --by NAME and --words TEXT unchanged")
    return {"at": now(), "by": a.by, "words": a.words}


def cmd_plan_approval(plan, a):
    md = plan_paths(plan)[0]
    read_plan(md)
    allocated = {}
    with port_lock(md), writing(plan, skip_unchanged=True) as st:
        if st["status"] == "merged":
            raise Refuse("finished", "a merged plan cannot be reapproved", "start a separate task for new work")
        entry = approval_words(a)
        acceptor = a.by if a.acceptor is None else a.acceptor
        if not single_line(acceptor) or (acceptor != a.by and not (a.authority or "").strip()):
            raise Refuse("no-authority", "a designated acceptor needs the human's grant", "give --acceptor NAME and --authority with the unchanged grant, or omit both")
        _, values = read_run_proposal(plan)
        if st.get("build_provider") and st["build_provider"] not in values.get("executors", {}):
            raise Refuse("build-assignment", "the proposed run removes the current build provider",
                         "retain the provider's profiles while this build is assigned")
        head, tail = read_plan(md)
        if problems := drift_diags(plan, st, head, tail):
            raise refuse_all(problems)
        lines = planning_lines(head)
        revision = approval_revision(st, lines, values)
        if a.revision != revision:
            raise Refuse("review-stale", "the plan or run configuration no longer matches the reviewed revision",
                         f"present the current proposal with {shlex.join([*cli_argv(plan), 'plan', 'review', md])} and obtain human approval")
        approval = {**entry, "revision": revision, "planning": lines, "run": digest(values), "acceptor": acceptor, "authority": a.authority}
        approvals = st.setdefault("approvals", {})
        previous = approvals.get("plan") or {}
        if any(previous.get(k) != v for k, v in approval.items() if k != "at"):
            if previous and (changes := run_changes(st.get("run", {}), values)):
                record(plan, st, "run file", None, "changed", ", ".join(f"{section} {key}" for section, key in changes))
            st["run"] = values
            approvals["plan"] = approval
            if st["status"] in LIVE and (allocated := allocate(plan, md, st, st.get("alloc"))):
                st["alloc"] = {**st.get("alloc", {}), **allocated}
                if "data_dir" in allocated:
                    os.makedirs(allocated["data_dir"], exist_ok=True)
            record(plan, st, "plan approval", previous.get("revision"), revision, a.words)
        if st["status"] == "draft":
            set_plan(plan, st, status="approved")
    print(f"Plan and run configuration approved by {a.by} at revision {revision}.")
    if allocated:
        print("facts: " + ", ".join(f"{k.replace('_', ' ')} {v}" for k, v in allocated.items()))
    if st["status"] == "approved":
        show_next(start_actions(plan, st, None))
    else:
        head, tail = read_plan(md)
        show_next(summary(plan, st, head, tail, workflow=True)["workflow"]["actions"])
    return 0


def awaiting_first_verdict(st):
    return all(v["kind"] == "evidence-owed" for v in st.get("verdicts", []))


def judge_evidence(st):
    return digest({k: st.get(k, []) for k in ("cycles", "rounds", "notes", "phases")})


def contract_digest(plan, st):
    return digest([planning_digest(plan), st.get("run"), st["base"], st["branch"]])


def require_judge(plan, st):
    require_consent(plan, st)
    cycle_of(st)
    settled(plan, st)
    v = (st.get("verdicts") or [None])[-1]
    if not v or not (v["kind"] == "pass" or v.get("stop")):
        raise Refuse("no-pass", "the judge's last verdict is not a pass or stopped round", "run the judge on the current evidence")
    tree = tree_of(plan, st)
    current = head_sha(None, tree)
    last = (st.get("lands") or [None])[-1]
    landed = (last and last.get("judge") == v["n"] and current == last["tip"]
              and (last["accepted"] or (not last["difference"] and tree_id(tree, current) == tree_id(tree, v["head"]))))
    if v.get("evidence") != judge_evidence(st) or v.get("contract") != contract_digest(plan, st) or not (current and (current == v["head"] or landed)):
        raise Refuse("judge-stale", "the judge does not cover the current commit, planning content or evidence", "run current checks and the judge, then land and page again")
    if st.get("rounds") and not st["rounds"][-1]["done"]:
        raise Refuse("round-open", "a round is still running", "finish the round and run the judge")
    return v


def page_binding(plan, st):
    key = "plan" if "plan" in st["approvals"] else "summary"
    return digest({key: acceptance_authority(st), "contract": contract_digest(plan, st),
                   "records": {k: st.get(k) for k in ("cycles", "rounds", "notes", "verdicts", "lands", "decisions", "phases")}})


def require_page(plan, st):
    require_consent(plan, st)
    lands = st.get("lands") or []
    if not lands:
        raise Refuse("no-land", "the branch is not landed", "run `land`, then `page` and obtain acceptance")
    require_judge(plan, st)
    last, tree = lands[-1], tree_of(plan, st)
    if head_sha(None, tree) != last["tip"] or git("rev-parse", f"refs/heads/{st['branch']}", check=False, cwd=tree).stdout.strip() != last["tip"] or (last["difference"] and not last["accepted"]) or dirty_lines(tree):
        raise Refuse("land-stale", "the current branch differs from its accepted land", "land the current result and render its page again")
    pg = st.get("page")
    if not pg:
        raise Refuse("no-page", "the landed result has no acceptance page", "render `page` with `--guide-file PATH` for the landed result and obtain acceptance")
    if pg.get("binding") != page_binding(plan, st):
        raise Refuse("page-stale", "the page no longer describes the current approval and evidence", "render `page` again with `--guide-file PATH` and obtain acceptance")
    return pg


def require_acceptance(plan, st):
    pg = require_page(plan, st)
    accepted = st.get("acceptance")
    if not accepted or accepted.get("page") != digest(pg):
        raise Refuse("acceptance-required", "the current page has no authorized acceptance", "record `accept --by NAME --words TEXT` from the human or designated acceptor")


def cmd_accept(plan, a):
    with writing(plan) as st:
        entry = approval_words(a)
        if st["status"] not in ("at the human gate", "passed"):
            raise Refuse("bad-status", f"the plan is {st['status']}", "acceptance follows the current page at the human gate")
        pg = require_page(plan, st)
        acceptor = acceptance_authority(st)["acceptor"]
        if a.by != acceptor:
            raise Refuse("unauthorized-acceptor", f"{a.by!r} has no acceptance grant; the acceptor is {acceptor!r}", "obtain the designated acceptor's unchanged words")
        st["acceptance"] = {**entry, "page": digest(pg)}
        set_plan(plan, st, status="passed", note=a.words)
        print(f"accept: current page accepted by {a.by}; passed")
    return 0


def cmd_approve(plan, as_json):
    md = plan_paths(plan)[0]
    read_plan(md)
    root = plan_root(md)
    derived = ("title", "territory", "skills", "spec", "waits", "waits_text")
    with port_lock(md), locked(plan):
        head, tail = read_plan(md)
        task = task_for(plan, root)
        st = load_state(plan)
        if task:
            ensure_task_tree(task, root)
            if st is None:
                require_discovery(task)
        history = plan_checkout(md)
        P, problems = parse_plan(head, task["tree"] if task else history, history=history)
        if problems:
            print("\n".join(f"{plan}:{n}: {message} — fix: repair the plan Markdown and run `pipeline.py approve`"
                            for n, message in sorted(problems)))
            return 1
        if st is None:
            if was_compiled(head) and P["status"] != "merged":
                raise missing_state(plan)
            if task and (P["branch"], P["base"], P["status"]) != (task["branch"], task["base"], "draft"):
                expected = f"draft · branch `{task['branch']}` · base `{task['base']}`"
                raise Refuse("task-identity", "a new task plan must be a draft on its registered branch and base", f"write Status: {expected}")
            how = "validated" if P["status"] == "draft" else "adopted"
            st = {"version": 1, "plan": os.path.basename(md), "status": P["status"],
                  "branch": P["branch"], "base": P["base"], "history": [], "phases": []}
            if how == "adopted" and (t := branch_tree(root, P["branch"])):
                st["tree"] = t
            record(plan, st, how, P["status"], st["status"], None if how == "validated" else "a plan without state, taken as its file stood")
            for ph in P["phases"]:
                st["phases"].append({"n": ph["n"], "status": ph["status"], **{k: ph[k] for k in derived}})
                if ph["status"] != "waiting":
                    record(plan, st, f"phase {ph['n']}", None, ph["status"], "taken as the file stood")
        else:
            how = "recompiled"
            old = {p["n"]: p for p in st["phases"]}
            new = {p["n"]: p for p in P["phases"]}
            for n, p in old.items():
                if p["status"] != "waiting" and (n not in new or new[n]["title"] != p["title"]):
                    raise Refuse("phase-gone", f"phase {n} ({p['title']}) is {p['status']} but the file no longer has it at that number",
                                 f"put phase {n} back; started phases keep their number and title")
            owned = code_owned(st, head)
            if owned:
                raise Refuse("drift", f"{plan}:{owned[0][0]}: `{owned[0][1]}` was edited by hand", f"restore it, or change it with `{owned[0][2]}`")
            for n, p in new.items():
                if n not in old and p["status"] != "waiting":
                    raise Refuse("drift", f"new phase {n} is marked {p['status']}", "write new phases as `waiting`")
            st["phases"] = [{**old.get(n, {"n": n, "status": "waiting"}), **{k: p[k] for k in derived}} for n, p in sorted(new.items())]
        had = "run" in st
        values, probs = read_run(plan)
        if probs and (had or how == "validated" or os.path.lexists(run_path(plan))):
            raise refuse_all(probs)
        facts = []
        if values is not None:
            if not plan_approval(st):
                st["run"] = values
            if st["status"] in LIVE:
                new = allocate(plan, md, st, st.get("alloc"))
                if new:
                    st["alloc"] = {**st.get("alloc", {}), **new}
                    if "data_dir" in new:
                        os.makedirs(new["data_dir"], exist_ok=True)
                    facts = ["facts: " + ", ".join(f"{k.replace('_', ' ')} {v}" for k, v in new.items())]
        st.update(title=P["title"], level=P["level"], epic=P["epic"], done=done_list(sections(head)["Done"][1]))
        head = save(plan, st, head, tail)
    words = len(" ".join(head + tail).split())
    over = []
    mine = [t for p in P["phases"] for t in p["territory"]]
    for path, status, other in other_plans(root, md):
        hit = sorted({t for p in other["phases"] for t in p["territory"] for m in mine if overlaps(t, m)})
        if hit:
            over.append({"plan": Path(path).stem, "status": status, "paths": hit})
    last = f"{graph_line(P['phases'])} · {P['level']} · {words} words"
    if as_json:
        print(json.dumps({"plan": plan_slug(st), "result": how, "status": st["status"], "graph": graph_line(P["phases"]),
                          "level": P["level"], "words": words, "overlaps": over, "alloc": st.get("alloc")}, ensure_ascii=False))
        return 0
    print(f"approve: {plan_slug(st)} {how}, status {st['status']}")
    for x in facts:
        print(x)
    for o in over:
        print(f"overlaps {o['plan']} ({o['status']}): {', '.join(o['paths'])}")
    print(last)
    return 0


def stale_evidence(plan, st):
    if st["status"] == "merged":
        return []
    check = require_acceptance if st.get("acceptance") else require_page if st.get("page") else require_judge if st.get("verdicts") else None
    if check:
        try:
            check(plan, st)
        except Refuse as error:
            return [f"{code}: {message} — fix: {fix}" for code, message, fix in error.diags]
    return []


@cache
def workflow_catalog():
    from runweld_release import read_workflow
    return read_workflow(Path(PACKAGE))


def stage_after(stage, event):
    return workflow_catalog()["stages"][stage]["next"][event]


def workflow_view(plan, stage, actions, optional=None):
    catalog = workflow_catalog()
    stages = catalog["stages"]
    current = catalog["order"].index(stage)
    rows = []
    for i, key in enumerate(catalog["order"]):
        definition = stages[key]
        state = (optional or {}).get(key, "complete" if i < current or (i == current and not actions) else "current" if i == current else "upcoming")
        rows.append({"id": key, **definition, "state": state})
    return {"plan": plan, "stage": stage, "stages": rows, "shared": catalog["shared"], "actions": actions}


def workflow_action(owner, kind, action, **context):
    return {"owner": owner, "kind": kind, "action": action, **context}


def plan_release(plan):
    from runweld_release import ReleaseError, run_pin
    try:
        return run_pin(plan_paths(plan)[0])
    except ReleaseError as error:
        raise Refuse("run-release", str(error), "restore the run's release record") from None


def cli_argv(plan=None, *, release=None):
    if (bundle := standalone_bundle()) is not None:
        release = release or (plan_release(plan) if plan else None) or bundle.name
        return [sys.executable, str(bundle.parents[3] / "bin/runweld"), "--release", release]
    return [sys.executable, os.path.realpath(__file__)]


def plan_command(plan, command, *args, cwd=None, release=None, **options):
    return {"cwd": cwd or plan_root(plan),
            "argv": [*cli_argv(plan, release=release), *command.split(), plan_paths(plan)[0], *map(str, args)],
            **({"options": options} if options else {})}


def run_action(plan, owner, action, command, *args):
    return workflow_action(owner, "run", action, **plan_command(plan, command, *args))


def work_action(owner, action, role, kind, **context):
    return workflow_action(owner, "work", action, role=role, assignment={"kind": kind, **context})


def show_workflow(view):
    print("Workflow" + (f" for {view['plan']}" if view["plan"] else "") + ":")
    if view["stage"] == "reproduce":
        print("Required before planning: bug reproduction.")
    for stage in view["stages"]:
        print(f"  {stage['label']} — {stage['state']}")
    show_next(view["actions"])


def show_discovery(stages):
    for name, stage in stages.items():
        entered = f" (entered {stage['entered']})" if stage.get("entered") else ""
        print(f"Discovery: {name} — {stage['status']}{entered}")
        for key in ("result", "reason", "command", "artifact"):
            if value := stage.get(key):
                print(f"  {key.capitalize()}: {value}")
        for question in stage["questions"]:
            label = "Unresolved at skip" if stage["status"] == "skipped" else "Open question"
            print(f"  {label}: {question}")


def show_next(actions):
    if actions:
        print("Next:")
        for step in actions:
            print(f"  {step['owner']} — {step['action']} [{step['kind']}]")
            for command in ([step] if step["kind"] == "run" else [step["command"]] if step.get("command") else []) + step.get("alternatives", []):
                show_command(command)
                if effects := step.get("effects"):
                    show_setup(effects)
            for evidence in step.get("evidence", []):
                print(f"    {evidence}")
            if authority := step.get("authority"):
                print(f"    Acceptance authority: {authority}")
            if executor := step.get("executor"):
                print(f"    Executor: {executor['provider']} {executor['tier']} — {executor['model']}" +
                      (f" (effort {executor['effort']})" if "effort" in executor else ""))
            assignment = step.get("assignment", {}) if step["kind"] != "run" else {}
            if steps := {key: val for key, val in assignment.items()
                         if key in ("phase", "territory", "grants", "range", "cases", "cycle", "fix", "round", "notes", "items", "verdict")}:
                print("    Assignment: " + ", ".join(f"{key} {val}" for key, val in steps.items()))
            if source := assignment.get("role_source"):
                print(f"    Role source: {source}\n    Protocol: {assignment['protocol']}")
            if brief := assignment.get("brief", {}).get("path"):
                print(f"    Prepared brief: {brief} (dispatch unverified)")
            for instruction in assignment.get("instructions", []):
                print(f"    In {assignment['cwd']}: {shlex.join(instruction)}")
            if channel := assignment.get("return_channel"):
                print(f"    Return: {channel['contact']} via {channel['method']}. Records: {channel['records']}")
            if records := step.get("records"):
                print(f"    Records: {records}")
            for report in assignment.get("reports", []):
                print(f"    {report['label']}:")
                show_command(report)
            if check := assignment.get("herdr_check"):
                print("    Before dispatch via Herdr:")
                show_command(check)
    else:
        print("Next: no remaining actions.")


def show_command(command):
    where = f"In {command['cwd']}: " if "cwd" in command else ""
    print(f"    {where}{shlex.join(command['argv'])}")
    if options := command.get("options"):
        print(f"    Inputs: {', '.join(options.values())}")


def cmd_workflow(as_json, stage=None):
    if stage is not None:
        catalog = workflow_catalog()
        if stage not in catalog["stages"]:
            raise Refuse("unknown-stage", f"unknown workflow stage {stage!r}", "choose from " + ", ".join(catalog["stages"]))
        definition = catalog["stages"][stage]
        if as_json:
            print(json.dumps({"id": stage, "shared": catalog["shared"], **definition}))
        else:
            print(definition["label"])
            for path in catalog["shared"] + definition["inputs"]:
                print(f"  {path}")
            for role, path in definition.get("roles", {}).items():
                print(f"  {role}: {path}")
            for condition, dependency in definition.get("when", {}).items():
                print(f"  {dependency['role']} for {condition}: {', '.join(dependency['inputs'])}")
            for event, target in definition["next"].items():
                print(f"  {event} -> {target}")
        return 0
    action = (work_action("Planner", "Run `runweld task start ID` for new work, or `runweld status --current` to resume.", "planner", "task-entry")
              if standalone_bundle() else work_action(
                  "Human and planner", "Discuss open decisions in a grill, or continue to planning. Offer an optional prototype before writing the plan.",
                  "planner", "grill"))
    view = workflow_view(None, "grill", [action])
    if as_json:
        print(json.dumps(view, ensure_ascii=False))
    else:
        show_workflow(view)
    return 0


def optional_workflow_history(head):
    history = {"grill": "unknown", "prototype": "unknown"}
    header = header_of(head)
    for line, masked in zip(header, fenced(header)):
        if masked:
            continue
        label, _, value = line.partition(":")
        value = value.strip()
        if label == "Grill" and value in ("done", "skipped"):
            history["grill"] = value
        elif label == "Prototype" and value:
            history["prototype"] = "skipped" if value == "none" else "done"
    return history


def phase_checks(st):
    return fill(st["run"], st.get("alloc"))["checks"]["phase"] if "run" in st else []


def missing_phase_checks(st, report):
    return [command for command in phase_checks(st) if command not in report.get("check_outcomes", {})]


def build_actions(plan, st, ready, provider):
    done = {p["n"] for p in st["phases"] if p["status"] == "done"}
    actions = []
    for p in st["phases"]:
        n = p["n"]
        owner = f"Implementer for phase {n}"
        if p["status"] == "in progress":
            if p.get("report") and (missing := missing_phase_checks(st, p["report"])):
                work = work_action(owner, f"Record the outcomes for {', '.join(missing)} with `phase report <plan> {n} --check COMMAND OUTCOME`.",
                                   "implementer", "phase", phase=n, checks=missing)
                bind_assignment(plan, st, "implementer", work)
                if executor := p.get("executor"):
                    work["executor"] = executor
                actions.append(work)
            elif p.get("report"):
                actions.append(run_action(plan, "Coordinator", f"Check the report and run `phase done <plan> {n}`.", "phase done", n))
            else:
                add_brief_actions(actions, plan, st, provider, "implementer", work_action(
                    owner, f"Work from the phase brief and record `phase report <plan> {n}`.", "implementer", "phase", phase=n), n)
        elif n in ready:
            actions.append(run_action(plan, "Coordinator", f"Start phase {n} with `phase start <plan> {n}`, then issue its implementer brief.", "phase start", n))
        elif p["status"] == "waiting":
            waits = [k for k in p["waits"] if k not in done]
            actions.append(workflow_action("Coordinator", "wait", f"Phase {n} waits for phase {', '.join(map(str, waits))} to finish.",
                                           phase=n, waits_for=waits))
    return actions


def workflow_brief(st, role):
    provider = " --provider PROVIDER" if "executors" in st.get("run", {}) else ""
    return f"brief {role}{provider} <plan>"


def brief_tier(brief, review_assignment=None):
    return "primary" if brief == "judge" or (brief == "reviewer" and review_assignment == "gate") else "secondary"


def role_definition(role):
    return next(stage for stage in workflow_catalog()["stages"].values() if role in stage.get("roles", {}))


def bind_assignment(plan, st, brief, work, *, legacy=None):
    role, assignment = work["role"], work["assignment"]
    md, state, _ = plan_paths(plan)
    tree = st["tree"] if legacy else tree_fact(plan, st)
    bundle, source = legacy or (Path(PACKAGE), role_definition(role)["roles"][role])
    release = bundle.name if legacy else None

    def report(label, command, *args, **options):
        return {"label": label, **plan_command(plan, command, *args, cwd=tree, release=release, **options)}

    if brief in ("implementer", "fix", "round"):
        args = (assignment["phase"],) if brief == "implementer" else ()
        command = "phase report" if brief == "implementer" else f"{brief} report"
        reports = [report("Report work", command, *args, became="--became TEXT", commits="--commit SHA", checks="--checks TEXT")]
        if brief == "implementer":
            reports[0]["options"]["phase_checks"] = "--check COMMAND OUTCOME"
            phase = phase_of(st, assignment["phase"])
            assignment.update(territory=phase["territory"], grants=phase.get("grants", []))
    elif brief == "reviewer":
        args = ("--assignment", assignment["id"], "--range", assignment["range"])
        reports = [report("Record a finding", "finding", *args, kind="--kind defect|convention|observation|unjudged",
                          text="--text TEXT", where="--where FILE:LINE (except unjudged)",
                          source="--source RULE_OR_PLAN_LINE (except unjudged)",
                          again="--again DEFECT_ID (if the defect survived a fix)"),
                   report("Complete the review", "review complete", *args)]
    elif brief == "verify":
        reports = [report("Record each verification result", "result", "--cycle", assignment["cycle"], "--head", assignment["head"],
                          case="--case NUMBER", outcome="--outcome OUTCOME", capture="--capture PATH_OR_OUTPUT", detail="--detail TEXT")]
    else:
        reports = [report("Record a verdict", f"verdict {kind}", report="--report TEXT", **options)
                   for kind, options in (("pass", {}), ("round", {"note": "--note TEXT CAUSE"}),
                                         ("question", {"question": "--question TEXT"}), ("evidence-owed", {"owed": "--owed ROLE"}))]
        for record in reports:
            if "evidence-owed" not in record["argv"]:
                record["options"]["decisions"] = "--decide ID ACTION REASON (for each open item or convention)"
                if awaiting_first_verdict(st):
                    record["options"].update(predicted="--predicted pass|round", engine="--engine NAME",
                                             predict="--predict TEXT CAUSE (for each predicted note)")
    assignment.update(cwd=tree, role_source=str(bundle / source),
                      protocol=str(bundle / "references/SESSIONS.md"),
                      instructions=[[*cli_argv(plan, release=release), role, "--plan", md]], reports=reports,
                      return_channel={"contact": "dispatching build coordinator",
                                      "method": "native message or agreed result channel",
                                      "records": state})
    if not legacy and standalone_bundle() is not None:
        assignment["herdr_check"] = plan_command(plan, "handoff herdr", workspace="--workspace ID", pane="--pane ID")


def herdr_handoff(plan, a):
    def refuse(message):
        raise Refuse("herdr-target", message, "inspect the live Herdr workspace and pane, then pass their IDs")

    if os.environ.get("HERDR_ENV") != "1":
        refuse("Herdr handoff must be checked from a Herdr session")
    try:
        result = subprocess.run(["herdr", "api", "snapshot"], capture_output=True, text=True, check=True, timeout=10)
        snapshot = json.loads(result.stdout)["result"]["snapshot"]
        workspaces, panes, agents = (snapshot[key] for key in ("workspaces", "panes", "agents"))
        workspace = next((w for w in workspaces if w.get("workspace_id") == a.workspace), None)
        pane = next((p for p in panes if p.get("pane_id") == a.pane and p.get("workspace_id") == a.workspace), None)
        agent = next((x for x in agents if x.get("pane_id") == a.pane and x.get("workspace_id") == a.workspace), None)
    except (OSError, subprocess.SubprocessError, ValueError, AttributeError, KeyError, TypeError):
        refuse("cannot read the live Herdr snapshot")
    if not workspace or not pane:
        refuse(f"pane {a.pane} is not live in workspace {a.workspace}")
    st = load_state(plan, required=True)
    tree = tree_of(plan, st)
    on_branch(st, tree)
    cwd = pane.get("foreground_cwd") or pane.get("cwd")
    if not isinstance(cwd, str) or os.path.realpath(cwd) != tree:
        refuse(f"pane {a.pane} is not in the assigned worktree {tree}")
    if a.agent:
        if not agent or agent.get("name") != a.agent or agent.get("agent_status") not in ("idle", "done"):
            refuse(f"{a.agent} is not a ready agent in pane {a.pane}")
    elif agent or pane.get("agent"):
        refuse(f"pane {a.pane} already has an agent; pass its name to check a continuation")
    print(f"handoff: Herdr workspace {a.workspace}, pane {a.pane} is live in {tree}")
    return 0


def brief_binding(plan, st, kind, provider, *, phase=None, cases=(), review=None):
    state = st.get("approvals", {})
    if kind == "implementer":
        scope = phase
    elif kind == "round":
        scope = st["rounds"][-1]["n"]
    elif kind == "fix":
        cycle = cycle_of(st)
        scope = (cycle_label(cycle), cycle["fixes"][-1]["n"])
    else:
        tree = tree_fact(plan, st)
        head = head_sha(None, tree)
        cycle = cycle_of(st)
        if kind == "reviewer":
            scope = ["review", *(review or review_target(st, cycle, tree, head))[:2]]
        elif kind == "verify":
            scope = [cycle_label(cycle), head, sorted(cases)]
        else:
            scope = [cycle_label(cycle), head, judge_evidence(st)]
        scope = [scope, (st.get("verdicts") or [None])[-1]]
    return digest([kind, provider, scope, state.get("plan") or state.get("summary")])


def prepared_brief(plan, st, kind, provider, args):
    if standalone_bundle() is None:
        return None
    phase = args[0] if kind == "implementer" else None
    cases = list(map(int, args[1].split(","))) if kind == "verify" and args else []
    marker = "Assignment binding: " + brief_binding(plan, st, kind, provider, phase=phase, cases=cases)
    prefix = f"{plan_slug(st)}.brief-{kind}-"
    found = []
    for candidate in Path(plan_paths(plan)[0]).parent.glob("*.md"):
        if not candidate.name.startswith(prefix) or candidate.is_symlink() or not candidate.is_file():
            continue
        try:
            with candidate.open(encoding="utf-8") as body:
                if any(line.rstrip("\n") == marker for line in body):
                    found.append((os.fstat(body.fileno()).st_mtime_ns, str(candidate)))
        except (OSError, UnicodeError):
            continue
    return max(found)[1] if found else None


def add_brief_actions(actions, plan, st, provider, brief, work, *args):
    actions.append(work)
    bind_assignment(plan, st, brief, work)
    assignment_args = args
    executor = phase_of(st, args[0]).get("executor") if brief == "implementer" else None
    provider = provider or st.get("build_provider")
    if executor:
        provider = executor["provider"]
        work["executor"] = executor
        args = (*args, "--provider", provider)
        needed = None
    elif provider is None and "executors" in st.get("run", {}):
        needed = workflow_action("Coordinator", "ask", "Supply the current provider to get executable brief commands.",
                                 input="provider", command=plan_command(plan, "status", provider="--provider NAME"))
    elif provider is not None:
        try:
            selection = executor_selection(plan, provider)
        except Refuse as error:
            _, message, fix = error.diags[0]
            needed = workflow_action("Coordinator", "ask", f"{message}. {fix}.", input="provider")
        else:
            tier = brief_tier(brief, work["assignment"].get("id"))
            work["executor"] = {"provider": provider, "source": selection["source"], "tier": tier, **selection[tier]}
            args = (*args, "--provider", provider)
            needed = None
    else:
        needed = None
    if needed is None:
        if path := prepared_brief(plan, st, brief, provider, assignment_args):
            work["action"] += " Recover the prepared brief. Inspect the host for a live assignment before dispatch or continuation."
            work["assignment"]["brief"] = {"path": path, "dispatch": "unverified"}
        else:
            step = run_action(plan, "Coordinator", f"Generate the `brief {brief}` assignment for {work['owner']}.", f"brief {brief}", *args)
            work["assignment"]["brief"] = {k: step[k] for k in ("argv", "cwd")}
            actions.append({**step, "role": work["role"], "assignment": work["assignment"]})
        actions.append(assignment_wait(brief, work))
    elif needed not in actions:
        actions.append(needed)


def assignment_wait(brief, work):
    return workflow_action("Coordinator", "wait", f"Only after confirming dispatch, wait for {work['owner']} to record the result before advancing.",
                           waiting_for=f"{brief}-report", assigned_to=work["owner"],
                           condition="after-dispatch", records=work["assignment"]["return_channel"]["records"])


def verification_workflow(plan, st, c, tree, provider):
    checked = checks_current(st, c, tree)
    actions = []
    if not checked:
        if c["kind"] == "gate":
            actions.append(run_action(plan, "Coordinator", "Full checks are missing or stale. Refresh the checks with `gate start <plan>`.", "gate start"))
        else:
            actions.append(work_action("Coordinator", "Full checks are missing or stale. Restore the checked round tree or obtain authorization for another round.",
                                       "coordinator", "checks", cycle=cycle_label(c)))
    head = head_sha(None, tree)
    target = review_target(st, c, tree, head)
    reviewed = review_is_current(c, target)
    label = cycle_label(c)
    verify_id, _ = verify_target(c, tree)
    baseline, baseline_cases, baseline_owed = baseline_evidence(st, c, tree)
    baseline_cases -= captured_cases(baseline_cases, latest_results(c), tree, head)
    after_checks = " Wait for current full checks first." if not checked else ""

    def evidence_work(role, work, *args):
        if checked:
            add_brief_actions(actions, plan, st, provider, role, work, *args)
        else:
            actions.append({**work, "kind": "wait", "waiting_for": "full-checks"})

    if not reviewed:
        issue = "stale" if c.get("reviews") else "unrecorded"
        need = f"Review the current baseline to recover missing evidence from {', '.join(baseline)}." if baseline else f"Review completion is {issue}."
        evidence_work("reviewer", work_action("Reviewer", f"{need}{after_checks} Use `{workflow_brief(st, 'reviewer')}` and record `review complete`.",
                                            "reviewer", "review", cycle=label, id=target[0], range=target[1]))
    pending = sorted(set(pending_results(st, c, tree)) | set(baseline_cases))
    if pending:
        cases = ", ".join(f"Done {n}" for n in pending)
        need = f"Drive {cases} on the current baseline to recover missing evidence." if baseline_cases else f"Current evidence is missing for {cases}."
        evidence_work("verify", work_action("Verify", f"{need}{after_checks} Drive the cases from `{workflow_brief(st, 'verify')}` and record the results.",
                                          "verify", "verify", cycle=label, id=verify_id, head=head, cases=pending))
    owed = outstanding_evidence(st, c, tree) + baseline_owed
    for request, cases in owed:
        role = request["owed"]
        if role == "verify" and not cases:
            actions.append(workflow_action("Coordinator", "ask", f"{request['report']} No Done cases are assigned to Verify. Give the judge the reason for an explicit E2E exception.",
                                           input="evidence-exception"))
            continue
        scope = " --cases " + ",".join(map(str, cases)) if cases else ""
        action = f"{request['report']}{after_checks} Use `{workflow_brief(st, role)}{scope}` to record the requested evidence."
        if role == "reviewer":
            evidence_work(role, work_action("Reviewer", action, role, "review", cycle=label, id=target[0], range=target[1], request=request["n"]))
        else:
            evidence_work(role, work_action("Verify", action, role, "verify", cycle=label, id=verify_id, head=head, cases=cases, request=request["n"]),
                          "--cases", ",".join(map(str, cases)))
    if checked and reviewed and len(c["fixes"]) < FIXES_PER_CYCLE and any(not taken(c, i["id"]) for i in items(c)):
        actions.append(run_action(plan, "Coordinator", "Open a fix for the outstanding items with `fix start <plan>`.", "fix start"))
    elif checked and reviewed and not any(v["owed"] == "reviewer" for v, _ in owed):
        judge = workflow_brief(st, "judge")
        if pending or owed:
            actions.append(workflow_action("Coordinator", "ask", f"For an explicit E2E exception, issue `{judge} --note REASON`. Record the reason with `verdict --evidence-note REASON`.",
                                           input="evidence-exception", command=judge_note_command(plan, st, provider, "REASON")))
        else:
            add_brief_actions(actions, plan, st, provider, "judge", work_action("Judge", f"Decide from the current evidence in `{judge}`.", "judge", "judge", cycle=label))
            return stage_after("build-verification", "evidence_ready"), actions
    return "build-verification", actions


def judge_note_command(plan, st, provider, note):
    provider = provider or st.get("build_provider")
    args = ("--provider", provider) if provider else ()
    options = {"note": f"--note {note}"}
    if not provider and st.get("run", {}).get("executors"):
        options["provider"] = "--provider NAME"
    return plan_command(plan, "brief judge", *args, **options)


def finish_workflow(plan, st, tip):
    status = st["status"]
    request = st.get("request") or {}
    current_request = request.get("tip") == tip and request.get("acceptance") == digest(st["acceptance"])
    if status.startswith("http"):
        if not current_request:
            return "finish", [work_action("Coordinator", "The linked request has no current finish record. Recover its accepted tip and authorization before confirming a merge.",
                                          "coordinator", "finish", request=status)]
        confirm = () if forge_of(status) == "github" else ("--merged",)
        return "finish", [workflow_action("Coordinator", "wait", f"Wait for {status} to merge, then confirm the merge.",
                                          waiting_for="merge", request=status, command=plan_command(plan, "finish", *confirm))]
    if (st.get("pushed") or {}).get("tip") == tip:
        return "finish", [{**work_action("Coordinator", "Find the outstanding request and record its link with `plan status`.", "coordinator", "request-link"),
                           "command": plan_command(plan, "plan status", link="LINK")}]
    if current_request:
        return "finish", [{**work_action("Coordinator", "Open the request on the forge and record its link with `plan status`.", "coordinator", "request-link"),
                           "command": plan_command(plan, "plan status", link="LINK")}]
    fin = st["run"]["finish"]
    if fin["how"] == "merge-request" and not remote_url(plan_root(plan_paths(plan)[0])):
        return "finish", [work_action("Coordinator", "Configure the request's `origin` remote before running `finish <plan>`.", "coordinator", "finish")]
    return stage_after("human-review", "accepted"), [run_action(plan, "Coordinator", f"Use `finish <plan>` for the approved ending, {fin['how']} into {fin['target']}.", "finish")]


def land_workflow(plan, st, tree, c, verdict, provider):
    land = (st.get("lands") or [None])[-1]
    current_land = land and (land.get("judge") == verdict["n"] or same_tree_land(st, c, tree, land, verdict["head"]))
    if current_land and land["difference"] and not land["accepted"]:
        return "judge", [workflow_action("Judge", "ask", "Decide the land hook's changes with `land accept <plan> --note WHY` or `land revert <plan>`.",
                                         input="land-difference", land=land["n"],
                                         alternatives=[plan_command(plan, "land accept", note="--note WHY"), plan_command(plan, "land revert")])]
    human_notes = [n["n"] for n in open_notes(st) if human_authored(n)]
    if current_land and st["status"] == "at the human gate" and st.get("page") and human_notes:
        return "human-review", [workflow_action("Human", "ask", "Review the open notes. If you authorize a round, the coordinator runs `round start <plan>`.",
                                                input="round-authorization", notes=human_notes,
                                                command=plan_command(plan, "round start"), evidence=[
                                                    note_line(st, n) for n in open_notes(st) if human_authored(n)])]
    try:
        if current_land:
            page = require_page(plan, st)
        else:
            require_judge(plan, st)
    except Refuse as error:
        code = error.diags[0][0]
        if code in ("land-stale", "no-page", "page-stale"):
            role = "judge" if code == "land-stale" else "coordinator"
            action = [work_action(role.title(), fix, role, "land" if code == "land-stale" else "page") for _, _, fix in error.diags]
            if code != "land-stale":
                for task in action:
                    task["command"] = page_command(plan, st)
            return "judge", action
        return verification_workflow(plan, st, c, tree, provider)
    if not current_land:
        if dirty := dirty_lines(tree):
            paths = ", ".join(line[3:] for line in dirty)
            return "judge", [work_action("Coordinator", f"Resolve the uncommitted paths before land: {paths}.", "coordinator", "land")]
        if not os.path.lexists(shape_path(plan)):
            return "judge", [run_action(plan, "Judge", "Create and edit the commit shape with `land draft <plan>`, then run `land <plan>`.", "land draft")]
        try:
            checked_land_shape(plan, st, tree)
        except Refuse as error:
            return "judge", [work_action("Judge", f"Prepare the current commit shape with `land draft <plan>` if needed. {message} — fix: {fix}.",
                                         "judge", "land", shape=shape_path(plan)) for _, message, fix in error.diags]
        return "judge", [run_action(plan, "Judge", "Use the current commit shape to run `land <plan>`.", "land")]
    status = st["status"]
    if status == "building":
        return "judge", [{**work_action("Coordinator", "Write the guide to the landed result and return it for human review.",
                                        "coordinator", "page"), "command": page_command(plan, st)}]
    accepted = (st.get("acceptance") or {}).get("page") == digest(page)
    if status == "at the human gate" and accepted:
        return "human-review", [run_action(plan, "Coordinator", "Restore the accepted status with `plan status <plan> passed`.", "plan status", "passed")]
    if not accepted:
        if status.startswith("http"):
            return "human-review", [run_action(plan, "Coordinator", 'Restore human review with `plan status <plan> "at the human gate"` and obtain current acceptance.',
                                               "plan status", "at the human gate")]
        authority = acceptance_authority(st)
        acceptor = authority["acceptor"]
        page_path = plan_paths(plan)[0] + "#human-gate"
        return stage_after("judge", "landed"), [workflow_action("Human", "ask",
            f"Review the current page at {page_path}. Use `accept` to record unchanged acceptance from {acceptor}.",
            input="acceptance", page=page_path, acceptor=acceptor, authority=authority.get("authority"),
            command=plan_command(plan, "accept", "--by", acceptor, words="--words ACCEPTANCE"),
            alternatives=[plan_command(plan, "page", "--show"),
                          plan_command(plan, "note add", text="--text FEEDBACK", cause="--cause CAUSE")])]
    return finish_workflow(plan, st, land["tip"])


def page_command(plan, st):
    options = {"guide": "--guide-file PATH"}
    if st["run"]["finish"]["how"] != "ff-only":
        options["message"] = "--message TEXT"
    return plan_command(plan, "page", **options)


def start_actions(plan, st, provider):
    options = {}
    argv = [*cli_argv(plan), "build", "start", plan_paths(plan)[0]]
    if not task_for(plan):
        options["base"] = "--base REF"
    presets = st.get("run", {}).get("executors", {})
    if provider and presets:
        argv.extend(("--provider", provider))
    elif len(presets) > 1:
        options["provider"] = "--provider " + "|".join(presets)
    return [workflow_action("Human", "ask", "Give a separate start instruction when ready. Approval alone starts nothing.",
                            input="start-authorization", command={"cwd": plan_root(plan), "argv": argv, "options": options})]


def workflow_next(plan, st, tree, ready, plan_drift, consent, provider):
    if st["status"] == "merged":
        if reason := st.get("cleanup_pending"):
            return "finish", [run_action(plan, "Coordinator", f"{reason}. Resolve it, then retry only the cleanup with `finish <plan>`.", "finish")]
        return "finish", []
    if plan_drift:
        return "plan", [work_action("Planner", fix, "planner", "repair-plan") for _, _, fix in plan_drift] + (
            [run_action(plan, "Planner", "Show the proposed changes with `plan review`.", "plan review")]
            if any(code == "plan-stale" for code, _, _ in consent) else [])
    if consent:
        if all(code in ("plan-unapproved", "run-stale", "plan-stale") for code, _, _ in consent):
            if os.path.isfile(run_path(plan)):
                return "plan", [run_action(plan, "Planner", "Show the complete plan, configuration and any changes with `plan review`.", "plan review"),
                                workflow_action("Human", "ask", "Approve the displayed revision or say what should change.", input="plan-approval")]
        return "plan", [work_action("Planner", f"{message} — fix: {fix}", "planner", "repair-file") for _, message, fix in consent]
    if st["status"] in ("draft", "approved"):
        return "plan", start_actions(plan, st, provider)
    pending = pending_check(st)
    if pending:
        step = check_action(plan, pending)
        if step["kind"] != "run":
            return "build-verification", [step]
    try:
        on_branch(st, tree_of(plan, st))
    except Refuse as error:
        return "build", [work_action("Coordinator", fix, "coordinator", "checkout") for _, _, fix in error.diags]
    if pending:
        return "build-verification", [step]
    if not st.get("cycles"):
        if actions := build_actions(plan, st, ready, provider):
            return stage_after("plan", "start_authorized"), actions
        return stage_after("build", "phases_complete"), [run_action(plan, "Coordinator", "Open build verification with `gate start <plan>`.", "gate start")]
    c = cycle_of(st)
    round_ = (st.get("rounds") or [None])[-1]
    if round_ and not round_["done"]:
        if not round_["report"]:
            actions = []
            add_brief_actions(actions, plan, st, provider, "round", work_action("Round implementer",
                f"Work from the round {round_['n']} brief and record `round report <plan>`.", "implementer", "round", round=round_["n"], notes=round_["notes"]))
            return "build", actions
        if missing := missing_note_sources(st, round_):
            return "build", [{**work_action("Coordinator", f"Record the note sources for round {round_['n']} before closing it.",
                                           "coordinator", "note-sources", round=round_["n"], notes=missing),
                              "alternatives": [plan_command(plan, "note edit", n, source="--source PREDICTION_OR_MISSED") for n in missing]}]
        return "build", [run_action(plan, "Coordinator", f"Check round {round_['n']}'s report and note sources, then run `round done <plan>`.", "round done")]
    fix = (c["fixes"] or [None])[-1]
    if fix and not fix["done"]:
        if not fix["report"]:
            actions = []
            add_brief_actions(actions, plan, st, provider, "fix", work_action("Fix implementer",
                f"Work from the fix {fix['n']} brief and record `fix report <plan>`.", "implementer", "fix", cycle=cycle_label(c), fix=fix["n"], items=fix["items"]))
            return stage_after("build-verification", "repair"), actions
        return stage_after("build-verification", "repair"), [run_action(plan, "Coordinator", f"Check fix {fix['n']}'s report and run `fix done <plan>`.", "fix done")]
    v = (st.get("verdicts") or [None])[-1]
    if not v or v["cycle"] != cycle_label(c):
        return verification_workflow(plan, st, c, tree, provider)
    if v["kind"] == "pass" or v.get("stop"):
        return land_workflow(plan, st, tree, c, v, provider)
    if v["kind"] == "question":
        if not v.get("answer"):
            return "judge", [workflow_action("Human", "ask", f"Answer the judge's question: {v['question']}", input="judge-answer", verdict=v["n"]),
                             workflow_action("Coordinator", "wait", f"Relay the human's answer with `{workflow_brief(st, 'judge')} --note ANSWER`.",
                                             waiting_for="judge-answer", command=judge_note_command(plan, st, provider, "ANSWER"))]
        try:
            require_current_checks(plan, st, c)
            require_evidence(st, c, tree, None)
        except Refuse:
            return verification_workflow(plan, st, c, tree, provider)
        actions = []
        add_brief_actions(actions, plan, st, provider, "judge", work_action(
            "Judge", f"Use `{workflow_brief(st, 'judge')}` with the recorded answer.", "judge", "judge", cycle=cycle_label(c), verdict=v["n"]))
        return "judge", actions
    if v["kind"] == "round":
        return "judge", [run_action(plan, "Coordinator", "Open the judge-ordered round with `round start <plan>`, then issue the round brief.", "round start")]
    return verification_workflow(plan, st, c, tree, provider)


def status_workflow(plan, head, stage, actions):
    history = optional_workflow_history(head)
    if standalone_bundle() and (task := task_for(plan)):
        if task.get("bug"):
            history = dict.fromkeys(history, "not applicable")
        else:
            discovery = read_discovery(plan)["stages"]
            history.update({name: discovery[name]["status"] for name in history if name in discovery})
    return workflow_view(plan_paths(plan)[0], stage, actions, history)


def pinned_response(bundle, plan, cwd, provider, command, *, release=None):
    from runweld_release import PROGRAM, ReleaseError, verify_release
    if bundle is None or not (release := release or plan_release(plan)) or release == bundle.name:
        return None
    engine = verify_release(bundle.parents[1], release) / PROGRAM
    if not command:
        return None
    argv = [sys.executable, str(engine), *command, "--json"]
    if provider:
        argv.extend(("--provider", provider))
    result = subprocess.run(argv, capture_output=True, text=True, cwd=cwd)
    if result.returncode:
        raise ReleaseError(result.stderr.strip() or result.stdout.strip() or f"{release} could not read {plan}")
    return json.loads(result.stdout)


def pinned_workflow(bundle, plan, cwd, provider, command):
    response = pinned_response(bundle, plan, cwd, provider, command)
    return response["workflow"] if response else None


def summary(plan, st, head, tail=None, *, workflow=False, provider=None):
    """-> the dict `status --json` prints."""
    plan_drift = drift_diags(plan, st, head, tail)
    consent = [] if st["status"] == "merged" else consent_diags(plan, st)
    cycles = []
    for c in st.get("cycles", []):
        cycles.append({**c, "list": items(c)})
    out = {**{k: st.get(k) for k in ("title", "status", "branch", "base", "epic", "level", "phases", "history")},
           "done": st.get("done", []), "verdicts": st.get("verdicts", []), "rounds": st.get("rounds", []), "notes": st.get("notes", []), "lands": st.get("lands", []), "land_stops": land_stops(st), "cycles": cycles, "plan": plan_slug(st), "ready": ready_phases(st), "tree": tree_fact(plan, st), "alloc": st.get("alloc"),
           "decisions": st.get("decisions") or [], "integration": st.get("integration"), "cleanup_pending": st.get("cleanup_pending"),
           "stale": stale_evidence(plan, st), "page": st.get("page"), "approvals": st.get("approvals", {}), "acceptance": st.get("acceptance"),
           "drift": [f"{m} — fix: {f}" for _, m, f in plan_drift + run_drift(plan, st) + consent]}
    if standalone_bundle() is not None:
        out.update(path=plan_paths(plan)[0], release=plan_release(plan))
    if "build_provider" in st:
        out["build_provider"] = st["build_provider"]
    for key in ("rounds", "notes"):
        out[key] = [dict(row, by="human") if human_authored(row) else row for row in out[key]]
    if workflow:
        out["workflow"] = status_workflow(plan, head, *workflow_next(plan, st, out["tree"], out["ready"], plan_drift, consent, provider))
    return out


def cmd_status(plan, as_json, cwd, current=False, provider=None, *, current_task=None, as_data=False):
    if plan is None:
        root = git("rev-parse", "--show-toplevel", check=False, cwd=cwd)
        if root.returncode:
            raise Refuse("no-repo", "not inside a git repository", "run it in the project")
        checkout = os.path.realpath(root.stdout.rstrip("\n"))
        main = main_worktree(checkout)
        scoped = current and checkout != os.path.realpath(main)
        bundle = standalone_bundle()
        installed = bundle is not None
        rows = []
        paths = inventory(main) if current_task is None else ([current_task] if os.path.lexists(current_task) else [])
        for path in paths:
            fn, full = path.name, str(path)
            st = load_state(full)
            try:
                head, tail = read_plan(full)
            except Refuse:
                if st is not None:
                    raise
                continue
            if st is None:
                m = next((STATUS_LINE.match(l) for l, f in zip(head, fenced(head)) if not f and STATUS_LINE.match(l)), None)
                if m and (m[1] in LIVE or installed):
                    task = task_for(full, main)
                    if scoped and (not (tree := task["tree"] if task else branch_tree(main, m[2])) or os.path.realpath(tree) != checkout):
                        continue
                    compiled = was_compiled(head)
                    row = {"plan": fn[:-3], "status": m[1] if installed else None, "ready": [], "nostate": True, "path": full,
                           "state_repair": f"restore {plan_paths(full)[1]}" if compiled else None}
                    if installed:
                        row.update(branch=m[2], base=m[3], tree=tree if scoped else (task["tree"] if task else branch_tree(main, m[2])),
                                   release=plan_release(full))
                    if current:
                        delegated = pinned_workflow(bundle, full, cwd, provider, ("status", full) if m[1] == "draft" and not compiled else ())
                        if delegated is None:
                            recorded = read_discovery(full)["stages"] if task else {}
                            if not compiled and task and discovery_in_use(task, recorded):
                                view = task_stage(task)
                                row["discovery"], delegated = view["discovery"], view["workflow"]
                            else:
                                action = (work_action("Planner", row["state_repair"], "planner", "repair-file") if compiled
                                          else run_action(full, "Planner", "Validate the draft with `approve <plan>`.", "approve") if m[1] == "draft"
                                          else work_action("Planner", "Inspect the historical plan and adopt it with `approve <plan>`.", "planner", "adopt-plan"))
                                delegated = status_workflow(full, head, "plan", [action])
                        row["workflow"] = delegated
                    rows.append((row, None))
            elif installed or st["status"] in LIVE or (current and (st["status"] == "approved" or st["status"].startswith("http"))):
                if scoped and os.path.realpath(tree_fact(full, st)) != checkout:
                    continue
                delegated = pinned_workflow(bundle, full, cwd, provider, ("status", full)) if current else None
                row = summary(full, st, head, tail, workflow=current and delegated is None, provider=provider)
                if delegated is not None:
                    row["workflow"] = delegated
                rows.append((row, st))
        if installed:
            tasks = task_rows(Path(main)) if current_task is None else [task_for(current_task, main)]
            for task in tasks:
                if task and not os.path.lexists(task["plan"]) and (not scoped or task["tree"] == checkout):
                    delegated = pinned_workflow(bundle, task["plan"], cwd, provider, ("task", "resume", task["id"])) if current else None
                    row = task_stage(task, workflow=current and delegated is None)
                    if delegated is not None:
                        row["workflow"] = delegated
                    rows.append((row, None))
        if as_data:
            return [r for r, _ in rows]
        if as_json:
            fields = ("plan", "status", "ready", "drift", "stale")
            print(json.dumps([r if (current or installed) else {k: r.get(k) for k in fields} for r, _ in rows], ensure_ascii=False))
            return 0
        for i, (r, st) in enumerate(rows):
            if current and i:
                print()
            if r.get("nostate"):
                fix = r["state_repair"] or "run `pipeline.py approve` on " + (r["path"] if current else "it")
                print(f"{r['plan']} — no state — fix: {fix}")
                if current:
                    show_discovery(r.get("discovery", {}))
                    show_workflow(r["workflow"])
            elif st is None:
                print(f"{r['plan']} — {r['status']} · {r['tree']}")
                if current:
                    show_discovery(r.get("discovery", {}))
                    show_workflow(r["workflow"])
            elif current:
                show_status(r, st)
            else:
                done = sum(p["status"] == "done" for p in r["phases"])
                print(f"{r['plan']} — {r['status']} · {done}/{len(r['phases'])} phases done · ready: {', '.join(map(str, r['ready'])) or 'none'}"
                      + ("".join(f"\n  {x}" for x in r["drift"])))
                if reason := r.get("cleanup_pending"):
                    print(f"  Cleanup pending: {reason}")
        return 0
    md = plan_paths(plan)[0]
    st = load_state(plan)
    head, tail = read_plan(md)
    if st is None:
        if was_compiled(head):
            raise missing_state(plan)
        root = plan_root(md)
        task = task_for(plan, root) if standalone_bundle() is not None else None
        draft, problems = parse_plan(head, root, check_references=False)
        if draft["status"] != "draft":
            raise missing_state(plan)
        if not problems:
            try:
                history = plan_checkout(md)
                _, problems = parse_plan(head, task["tree"] if task else history, history=history)
            except Refuse as error:
                problems = error.diags
        action = "Validate the draft with `approve <plan>` before presenting it for human approval."
        _, run_problems = read_run(plan)
        step = (work_action("Planner", f"Prepare the draft and run file. {action}", "planner", "plan") if problems or run_problems
                else run_action(plan, "Planner", action, "approve"))
        discovery = read_discovery(md)["stages"] if task else {}
        view = (task_stage(task)["workflow"] if task and discovery_in_use(task, discovery)
                else status_workflow(plan, head, "plan", [step]))
        if as_json or as_data:
            row = {**draft, "plan": os.path.basename(md)[:-3], "workflow": view}
            if standalone_bundle() is not None:
                row.update(path=md, release=plan_release(plan), tree=task["tree"] if task else branch_tree(root, draft["branch"]))
                if task:
                    row["discovery"] = discovery
            if as_data:
                return row
            print(json.dumps(row, ensure_ascii=False))
        else:
            print(f"Status: draft · branch `{draft['branch']}` · base `{draft['base']}`")
            show_discovery(discovery)
            show_workflow(view)
        return 0
    s = summary(plan, st, head, tail, workflow=True, provider=provider)
    if as_data:
        return s
    if as_json:
        print(json.dumps(s, ensure_ascii=False))
    else:
        show_status(s, st)
    return 0


def bind_legacy_planning_action(step, plan, tree, bundle):
    assignment = step.get("assignment", {})
    kind = assignment.get("kind")
    if step.get("role") != "planner" or "instructions" in assignment or kind not in ("grill", "plan", "task-start"):
        return
    if kind == "task-start":
        step.update(kind="run", cwd=plan_root(plan), argv=[*cli_argv(plan, release=bundle.name), "task", "start", Path(plan).stem])
        return
    guides = ("grill", "plan") if kind == "grill" else ("plan",)
    assignment.update(cwd=tree, instructions=[[*cli_argv(plan, release=bundle.name), guide, "--plan", plan] for guide in guides],
                      role_source=str(bundle / "workflow" / kind / "GUIDE.md"),
                      protocol=str(bundle / "references/SESSIONS.md"),
                      reports=[{"label": "Validate the written draft without approving it",
                                **plan_command(plan, "approve", cwd=tree, release=bundle.name)}],
                      return_channel={"contact": "human and planner",
                                      "method": "save the decisions in the draft",
                                      "records": plan})


def legacy_brief(plan, head, status, brief, work):
    assignment = work["assignment"]
    scopes = {"implementer": ("phase",), "fix": ("cycle", "fix"), "round": ("round",),
              "reviewer": ("id",), "verify": ("cycle",), "judge": ("cycle",)}
    scope = "-".join(str(assignment[key]) for key in scopes[brief])
    stem = f"{Path(plan).stem}.brief-{brief}-{scope}"
    pattern = stem + ("*.md" if brief in ("reviewer", "verify") else ".md")
    release = status.get("release") or "unversioned run"
    label = f"{brief} phase {assignment['phase']}" if brief == "implementer" else brief
    expected = [f"Plan: {plan}", f"Tree: {assignment['cwd']}", f"Branch: {status['branch']}",
                f"Assignment: {label}", f"Run release: {release}", f"Role source: {assignment['role_source']}"]
    grants = assignment.get("grants", [])
    if brief == "implementer":
        if grants == ["none"]:  # The legacy brief uses the same text for no grants.
            return None
        if not (phase := phase_brief_text(head, assignment["phase"])):
            return None
        phase.append(f"Grants: {', '.join(grants) or 'none'}")
    if executor := work.get("executor"):
        expected += [f"Executor {k}: {executor[k]}" for k in ("provider", "tier", "model", "effort") if k in executor]
    if brief in ("reviewer", "verify", "judge"):
        expected.append(f"HEAD: {head_sha(None, assignment['cwd'])}")
    if brief == "judge" and assignment.get("verdict"):
        answer = status["verdicts"][-1].get("answer")
        expected.append(f"The user's answer: {answer}")
    approved = max((record.get("at") or "" for record in status.get("approvals", {}).values()), default="")
    # Legacy briefs lack an assignment digest. Match the saved scope and pinned context without inferring dispatch.
    found = []
    for path in Path(plan).parent.glob(pattern):
        if path.is_symlink() or not path.is_file():
            continue
        try:
            mtime = path.stat().st_mtime
            if datetime.datetime.fromtimestamp(mtime, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") < approved:
                continue
            lines = read_required(path, "brief", "restore the prepared brief").split("\n")
        except (OSError, Refuse):
            continue
        if not all(line in lines for line in expected):
            continue
        if brief == "implementer":
            # The writer's first section contains the literal phase before its grant metadata.
            start = next((i for i, line in enumerate(lines) if line.startswith("## ")), len(lines))
            if lines[start:start + len(phase)] != phase:
                continue
        if brief == "reviewer":
            binding = shlex.join([plan, "--assignment", assignment["id"], "--range", assignment["range"]])
            if not any(line.startswith("- Complete the review: ") and line.endswith(binding) for line in lines):
                continue
        if brief == "verify":
            body = "\n".join(lines).partition("## Cases to drive\n")[2].partition("\nHow to run the system:")[0]
            if not all(re.search(rf"(?m)^{n}\. ", body) for n in assignment["cases"]):
                continue
        found.append((mtime, str(path)))
    return max(found)[1] if found else None


def bind_legacy_actions(status, workflow, plan, head, task, bundle, provider):
    actions = workflow["actions"]
    roles = {role: source for stage in workflow["stages"] for role, source in stage.get("roles", {}).items()}
    briefs = {digest(step["assignment"]): step for step in actions
              if step["kind"] == "run" and step.get("role") and step["argv"][4:5] == ["brief"]}
    added, prepared = [], []

    def command(name, *args, **options):
        return plan_command(plan, name, *args, release=bundle.name, **options)

    def consent_evidence(name):
        for i, message in enumerate(status.get("drift", [])):
            fact, _, fix = message.partition(" — fix: ")
            if f"`{name}" in fix or f"`pipeline.py {name}" in fix:
                status["drift"][i] = fact

    for step in actions:
        if not step.get("command"):
            approval = step.get("input")
            if approval == "run-approval":
                consent_evidence("run approve")
                step.update(action=f"Review {run_path(plan)} with the human and record their unchanged approval of this run.",
                            command=command("run approve", by="--by NAME", words="--words TEXT"),
                            alternatives=[command("run show")])
            elif approval == "summary-approval":
                consent_evidence("summary approve")
                step.update(action="Present a summary linked to this plan and record the human's unchanged approval.",
                            command=command("summary approve", file="--file PATH", by="--by NAME", words="--words TEXT",
                                            acceptor="--acceptor NAME (for designated acceptance)",
                                            authority="--authority TEXT (the human's grant for designated acceptance)"))
            elif step.get("waiting_for") == "start-instruction":
                step["command"] = command("build start", **({} if task else {"base": "--base REF"}))
            elif approval == "provider":
                step.update(action="Supply the current provider to get executable brief commands.",
                            command=command("next --plan", provider="--provider NAME"))
            elif step.get("waiting_for") == "judge-answer" or (approval == "evidence-exception" and "brief judge" in step["action"]):
                note = "ANSWER" if step.get("waiting_for") == "judge-answer" else "REASON"
                step["command"] = command("brief judge", *(("--provider", provider) if provider else ()),
                                          note=f"--note {note}", **({} if provider else {"provider": "--provider NAME"}))
        if step["kind"] != "work":
            continue
        bind_legacy_planning_action(step, plan, status["tree"] or plan_root(plan), bundle)
        role, assignment = step.get("role"), step.get("assignment", {})
        if role not in roles or "instructions" in assignment:
            continue
        kind = assignment["kind"]
        if kind not in ("phase", "review", "verify", "fix", "round", "judge"):
            continue
        brief = {"phase": "implementer", "review": "reviewer"}.get(kind, kind)
        generation = briefs.get(digest(assignment))
        bind_assignment(plan, status, brief, step, legacy=(bundle, roles[role]))
        if generation:
            if path := legacy_brief(plan, head, status, brief, step):
                assignment["brief"] = {"path": path, "dispatch": "unverified"}
                step["action"] += " Recover the prepared brief. Inspect the host for a live assignment before dispatch or continuation."
                prepared.append(generation)
            else:
                assignment["brief"] = {"argv": generation["argv"], "cwd": generation.get("cwd", plan_root(plan))}
                generation["assignment"] = assignment
            added.append(assignment_wait(brief, step))

    return [step for step in actions if step not in prepared] + added


def cmd_next(bundle, a, selected_plan, legacy_release):
    from runweld_release import project_root
    cwd = Path.cwd()
    project = project_root(cwd)
    if a.id and selected_plan is None:
        raise Refuse("no-task", f"there is no task {a.id}", "run `runweld next` to list tasks or `runweld task start ID` for new work")
    view = {"project": str(plan_root(plan_paths(selected_plan)[0])) if selected_plan else str(project) if project else None}
    if selected_plan:
        plan = plan_paths(selected_plan)[0]
        task = task_for(plan)
        has_plan = os.path.lexists(plan)
        head = []
        goal = task.get("goal") if task else None
        if legacy_release:
            command = ("task", "resume", task["id"]) if task and not has_plan else ("status", plan)
            status = pinned_response(bundle, plan, cwd, a.provider, command, release=legacy_release)
            if not has_plan:
                status.update(status="planning", plan=task["id"], ready=[])
            discovery = status.get("discovery", {})
        else:
            discovery = read_discovery(plan)["stages"] if task else {}
            if task and (not has_plan or (discovery_in_use(task, discovery) and not load_state(plan))):
                status = task_stage(task)
            else:
                status = cmd_status(plan, False, cwd, provider=a.provider, as_data=True)
        if has_plan:
            head, _ = read_plan(plan)
            goal = "\n".join(sections(head).get("Result", (0, []))[1]).strip() or goal
        workflow = status.pop("workflow")
        stage = workflow["stage"]
        actions = (bind_legacy_actions(status, workflow, plan, head, task, bundle.parent / legacy_release, a.provider)
                   if legacy_release else workflow["actions"])
        for step in actions:
            if step["kind"] == "run":
                step.setdefault("cwd", view["project"])
        purpose = ("Prepare the task worktree if needed, reproduce the failure and save the cause and red evidence."
                   if stage == "reproduce" else workflow_catalog()["stages"][stage].get("purpose", stage))
        view.update(task={**status, "id": status["plan"], "path": plan, "release": legacy_release or status["release"],
                          "artifacts": task["artifacts"] if task else str(Path(plan).parent),
                          "goal": goal, **({"discovery": discovery} if task else {})},
                    stage=stage, purpose=purpose, actions=actions, evidence=next_evidence(status))
    elif not project:
        view["actions"] = [workflow_action("Human", "ask", "Open a Git checkout, clone one, or run `git init` for a new project.", input="project")]
    else:
        root = str(project)
        config, lock = (project / ".runweld" / name for name in ("config.toml", "runweld.lock"))
        if not (config.is_file() and lock.is_file()):
            view["actions"] = [workflow_action("Human", "run", "Set up project defaults and executors with `runweld init`.",
                                               cwd=root, argv=[*cli_argv(release=legacy_release), "init"])]
        elif git("rev-parse", "--verify", "HEAD", check=False, cwd=root).returncode:
            view["actions"] = [workflow_action("Human", "ask", "Make an initial Git commit before creating a task worktree.", input="base-commit")]
        else:
            rows = cmd_status(None, False, cwd, as_data=True)
            tasks = [{"id": row["plan"], **{k: row[k] for k in ("path", "status", "tree", "release")},
                      **({"title": row["title"]} if row.get("title") else {})}
                     for row in rows if row["status"] != "merged" or row.get("cleanup_pending")]
            actions = []
            for task in tasks:
                path = task["path"]
                select = [task["id"]] if task_for(path, project) else ["--plan", path]
                actions.append(workflow_action("Planner", "run", f"Inspect {task['id']} ({task['status']}) with `{shlex.join(['runweld', 'next', *select])}`.",
                                               cwd=root, argv=[*cli_argv(path), "next", *select]))
            actions.append(workflow_action("Planner", "ask", "For new work, choose a task ID and run `runweld task start ID --goal TEXT`. Add `--bug` for a reproduction.",
                                           input="task-id"))
            view.update(tasks=tasks, actions=actions)
    if a.json:
        print(json.dumps(view, ensure_ascii=False))
    else:
        if view["project"]:
            print(f"Project: {view['project']}")
        if task := view.get("task"):
            print(f"Task: {task['id']} — {task.get('title') or task['status']}")
            if task["goal"]:
                print(f"Goal: {task['goal']}")
            print(f"Stage: {view['stage']} — {view['purpose']}")
            print(f"Branch: {task['branch']} · Base: {task['base']} · Release: {task['release']}")
            print(f"Tree: {task['tree']}\nPlan: {task['path']}\nArtifacts: {task['artifacts']}")
            show_discovery(task.get("discovery", {}))
            for decision in task.get("decisions") or []:
                print(f"Decision ({decision['by']}): {decision['question']} — {decision['answer']}")
            if approval := task.get("approvals", {}).get("plan"):
                print(f"Plan approval: {approval['by']} at revision {approval['revision']}")
            if view["evidence"]:
                print("Evidence:")
                for fact in view["evidence"]:
                    print(f"  {fact}")
        show_next(view["actions"])
    return 0


def next_evidence(status):
    evidence = []
    for phase in status.get("phases", []):
        if report := phase.get("report"):
            evidence.append(f"Phase {phase['n']} ({phase['status']}): {report['became']}")
    if status.get("cycles"):
        cycle = status["cycles"][-1]
        if run := selected_run(cycle):
            evidence.extend(show_run(run, True))
        evidence.extend(show_cycle(cycle, status))
        evidence.extend(show_judging(status))
        evidence.extend(show_land(status))
    if acceptance := status.get("acceptance"):
        evidence.append(f"Result accepted by {acceptance['by']}: {acceptance['words']}")
    if integration := status.get("integration"):
        destination = integration.get("commit", integration.get("request"))
        evidence.append(f"Integrated {integration['how']} into {integration['target']}: {destination}")
    if pending := status.get("cleanup_pending"):
        evidence.append(f"Cleanup pending: {pending}")
    return evidence + status.get("drift", []) + status.get("stale", [])


def show_status(s, st):
    print(f"{plan_slug(st)} — {st['title']}")
    print(f"Status: {st['status']} · branch `{st['branch']}` · base `{st['base']}`")
    if "release" in s:
        print("Release: " + (s["release"] or "unversioned run"))
    if approval := st.get("approvals", {}).get("plan"):
        print(f"Plan approval: {approval['by']} at revision {approval['revision']}")
    t = s["tree"]
    print(f"Tree: {t}" + ("" if os.path.isdir(t) else " (gone)"))
    show_workflow(s["workflow"])
    if st.get("epic"):
        print(f"Epic: {st['epic']['path']} · row {st['epic']['row']}")
    if st.get("alloc"):
        print("Run: " + " · ".join(f"{k.replace('_', ' ')} {v}" for k, v in st["alloc"].items()))
    for c in s["cycles"]:
        if c["kind"] == "gate":
            print(f"Gate: {c['level']}" + (f" (raised by {', '.join(c['raised_by'])})" if c["raised_by"] else ""))
        if run_ := selected_run(c):
            print("\n".join(show_run(run_, True)).replace("checks at", "Checks at", 1).replace(" (reused, run", " (run", 1))
        lines = show_cycle(c, st)
        if lines:
            print(f"Cycle {cycle_label(c)}:")
        for l in lines:
            print(l)
    for l in show_judging(st):
        print(l)
    for l in show_land(st):
        print(l)
    print("Phases:")
    for p in st["phases"]:
        print(f"  {p['n']}. {p['title']} — {p['status']}" + (f" (waits for {', '.join(map(str, p['waits']))})" if p["waits"] and p["status"] == "waiting" else ""))
        if p.get("grants"):
            print(f"     grants: {', '.join(p['grants'])}")
        if p.get("report"):
            print(f"     report: {p['report']['became']} (commits: {', '.join(c[:7] for c in p['report']['commits'])})")
            for command, outcome in p["report"].get("check_outcomes", {}).items():
                print(f"     check: {command} — {outcome}")
    print(f"Ready: {', '.join(map(str, s['ready'])) or 'none'}")
    notes = [h for h in st["history"] if h.get("note")]
    if notes:
        print("Notes:")
        for h in notes:
            print(f"  {h['at']} {h['what']} {'—' if h['from'] is None else h['from']} → {h['to']} @{(h['sha'] or '-')[:7]}: {h['note']}")
    if st.get("decisions"):
        print("Decisions:")
        for d in st["decisions"]:
            print(f"  {d['at']} phase {d['phase'] or '-'} by {d['by']}: {d['question']}\n"
                  f"    from: {d['source']}\n    answer: {d['answer']}\n    why: {d['why']}\n    cost if wrong: {d['cost']}")
    for d in s["drift"]:
        print(f"Drift: {d}")
    for d in s["stale"]:
        print(f"Evidence: {d}")


def cmd_plan(command, plan, value, note):
    with writing(plan) as st:
        if command == "status":
            if value == "passed":
                require_acceptance(plan, st)
            elif value == "approved":
                require_consent(plan, st)
            elif value == "building":
                require_consent(plan, st)
                if st["status"] == "draft" or not st.get("tree"):
                    raise Refuse("build-required", "build start has not created the branch", "run `build start --base REF`")
            elif value == "at the human gate":
                require_page(plan, st)
            elif value == "merged" and st["status"] != "merged":
                raise Refuse("finish-required", "merged is recorded only by finish", "run `finish` after current acceptance")
            elif value.startswith("http"):
                request = st.get("request")
                if not request or request["tip"] != git("rev-parse", st["branch"], cwd=plan_root(plan_paths(plan)[0])).stdout.strip() or request["acceptance"] != digest(st.get("acceptance")):
                    raise Refuse("no-request", "no current finish handoff permits recording a request link", "finish the accepted result first")
                require_acceptance(plan, st)
            old = st["status"]
            set_plan(plan, st, status=value, note=note)
            print(f"plan status: {plan_slug(st)} {old} → {st['status']}")
        else:
            r = git("rev-parse", "--verify", "-q", f"{value}^{{commit}}", check=False, cwd=os.path.dirname(plan_paths(plan)[0]))
            if r.returncode:
                raise Refuse("unknown-ref", f"{value} is not a commit", "name a tag, branch or SHA")
            old = st["base"]
            set_plan(plan, st, base=r.stdout.strip(), note=note)
            print(f"plan base: {plan_slug(st)} {old} → {st['base']}")
    return 0


# -- the build commands

def phase_of(st, n):
    ph = next((p for p in st["phases"] if p["n"] == n), None)
    if ph is None:
        raise Refuse("no-phase", f"the plan has no phase {n}", "phases: " + ", ".join(str(p["n"]) for p in st["phases"]))
    return ph


def main_worktree(root):
    from runweld_release import project_root
    return str(project_root(root) or root)


def branch_tree(root, branch):
    from runweld_release import worktrees
    return next((str(path) for path, name in worktrees(root) if name == branch), None)


def tree_fact(plan, st):
    """The tree the plan's branch lives in: where git has it checked out, else the recorded one, else the main checkout."""
    root = plan_root(plan_paths(plan)[0])
    if task := task_for(plan, root):
        return task["tree"]
    return branch_tree(root, st["branch"]) or st.get("tree") or plan_checkout(plan_paths(plan)[0])


def tree_of(plan, st):
    t = tree_fact(plan, st)
    if task := task_for(plan):
        ensure_task_tree(task, plan_root(plan_paths(plan)[0]))
    if not os.path.isdir(t):
        raise Refuse("tree-gone", f"the plan's tree {t} does not exist",
                     f"check the branch {st['branch']} out again, for example `git worktree add {t} {st['branch']}`")
    return t


def on_branch(st, tree):
    """Refuse when the tree git would act in is not on the plan's branch."""
    here = git("branch", "--show-current", check=False, cwd=tree).stdout.strip()
    if here != st["branch"]:
        raise Refuse("wrong-branch", f"the tree {tree} is on {here or 'a detached head'}, the plan's branch is `{st['branch']}`", f"check `{st['branch']}` out there, or add a worktree for it")


def inside(path, roots):
    p = norm(path)
    return any(p == norm(t) or p.startswith(norm(t) + "/") for t in roots)


def owner_of(st, path, skip=None):
    """The running phase whose territory or grants hold path, or None."""
    return next((p for p in st["phases"] if p["status"] == "in progress" and p["n"] != skip
                 and any(overlaps(path, t) for t in p["territory"] + p.get("grants", []))), None)


def cmd_build_start(plan, base, worktree, branch, note, provider, as_json):
    md = plan_paths(plan)[0]
    root = plan_root(md)
    with port_lock(md), writing(plan, skip_unchanged=True) as st:
        require_consent(plan, st)
        resumed = st.get("tree") and (st["status"] in LIVE or st["status"].startswith("http"))
        if resumed:
            requested_base = git("rev-parse", "--verify", "-q", "--end-of-options", f"{base}^{{commit}}",
                                 check=False, cwd=root).stdout.strip() if base is not None else st["base"]
            if (provider and st.get("build_provider") and provider != st["build_provider"]
                    or branch and branch != st["branch"]
                    or worktree and os.path.realpath(worktree) != os.path.realpath(st["tree"])
                    or requested_base != st["base"]):
                raise Refuse("build-assignment", "build start cannot change the existing provider, base, branch or worktree",
                             "repeat without overrides to see the current assignment")
            facts = []
        elif st["status"] == "approved":
            facts = start_build(plan, st, md, root, base, worktree, branch, note, provider)
        else:
            raise Refuse("not-approved", f"{plan_slug(st)} is {st['status']}, not approved",
                         "review and approve the current plan before starting")
    head, tail = read_plan(md)
    view = summary(plan, st, head, tail, workflow=True, provider=st.get("build_provider") or provider)
    active = [phase for phase in st["phases"] if phase["status"] == "in progress"]
    if as_json:
        print(json.dumps({**view, "resumed": bool(resumed), "active_phases": active, "facts": facts}, ensure_ascii=False))
    else:
        print(f"build start: {plan_slug(st)} {'resumed' if resumed else 'building'} on {st['branch']} at {st['base'][:7]}, tree {st['tree']}")
        for fact in facts:
            print(f"facts: {fact}")
        for phase in active:
            executor = phase.get("executor")
            print(f"Active phase {phase['n']}: {phase['title']} — " +
                  (f"{executor['provider']} {executor['model']}" + (f" (effort {executor['effort']})" if "effort" in executor else "")
                   if executor else "no executor assignment recorded"))
        show_next(view["workflow"]["actions"])
    return 0


def start_build(plan, st, md, root, base, worktree, branch, note, provider):
    presets = st.get("run", {}).get("executors", {})
    if not provider and len(presets) == 1:
        provider = next(iter(presets))
    if not provider and presets and "plan" in st.get("approvals", {}):
        raise Refuse("provider-required", "build start needs the coordinator's provider",
                     "pass --provider with one of " + ", ".join(presets))
    if provider:
        executor_selection(plan, provider)
        st["build_provider"] = provider
    task = task_for(plan, root)
    if not task:
        root = plan_checkout(md)
    if task:
        ensure_task_tree(task, root)
        if worktree or branch or st["branch"] != task["branch"] or st["base"] != task["base"]:
            raise Refuse("task-identity", "build cannot replace the registered task branch, base or worktree",
                         "use `runweld build start PLAN` to reuse the task checkout")
        base = base or task["base"]
    elif not base:
        raise Refuse("base-required", "this plan started without a registered task checkout", "pass --base REF")
    r = git("rev-parse", "--verify", "-q", "--end-of-options", f"{base}^{{commit}}", check=False, cwd=root)
    if r.returncode:
        raise Refuse("unknown-ref", f"{base} is not a commit", "name a tag, branch or SHA with --base")
    sha, branch = r.stdout.strip(), branch or st["branch"]
    if task and sha != task["base"]:
        raise Refuse("task-base", f"the task started at {task['base']}, not {sha}", "omit --base to reuse the registered checkout")
    alloc = ensure_allocation(plan, md, st) if task else allocate(plan, md, st)
    if task:
        tree = task["tree"]
        was = branch
        dirty = len(dirty_lines(tree))
    else:
        if git("rev-parse", "--verify", "-q", f"refs/heads/{branch}", check=False, cwd=root).returncode == 0:
            raise Refuse("branch-exists", f"branch {branch} already exists", "delete it, or name another with `build start --branch NAME`")
        was = git("branch", "--show-current", cwd=root).stdout.strip() or "(detached)"
        dirty = len(git("status", "--porcelain", cwd=root).stdout.splitlines())
        if worktree:
            tree = os.path.abspath(worktree)
            r = git("worktree", "add", "-b", branch, tree, sha, check=False, cwd=root)
        else:
            tree = root
            r = git("switch", "-c", branch, sha, check=False, cwd=root)
        if r.returncode:
            raise Refuse("git-failed", r.stderr.strip(), "fix the tree and run it again")
        if alloc:
            st["alloc"] = alloc
            if "data_dir" in alloc:
                os.makedirs(alloc["data_dir"], exist_ok=True)
    st["tree"] = tree
    set_plan(plan, st, status="building", base=sha, branch=branch, note=note)
    facts = [", ".join(f"{k.replace('_', ' ')} {v}" for k, v in alloc.items())] if alloc else []
    return facts + [f"was on {was}; tree was " + (f"dirty ({dirty} paths)" if dirty else "clean")]


def phase_start_ready(st, n, note):
    ph = phase_of(st, n)
    if ph["status"] == "in progress":
        raise Refuse("running", f"phase {n} is already in progress", "report and finish it with `pipeline.py phase done`")
    if st["status"] in ("draft", "approved"):
        raise Refuse("not-building", f"{plan_slug(st)} has not started the build",
                     "run `build start` after the human's separate start instruction")
    if not note:
        if ph["status"] == "done":
            raise Refuse("is-done", f"phase {n} is done", "pass --note with the reason to start it again")
        open_ = [x for x in ph["waits"] if phase_of(st, x)["status"] != "done"]
        if open_:
            raise Refuse("waits", f"phase {n} waits for {', '.join(map(str, open_))}, not done",
                         "finish them first, or pass --note with the reason to start now")
    return ph


def cmd_phase_start(plan, n, note):
    if task_for(plan):
        phase_start_ready(load_state(plan, required=True), n, note)
        cmd_task_setup(plan, implicit=True)
    with writing(plan) as st:
        require_consent(plan, st)
        ph = phase_start_ready(st, n, note)
        if not ph.get("executor") and (provider := st.get("build_provider")):
            selected = executor_selection(plan, provider)
            ph["executor"] = {"provider": provider, "source": selected["source"], "tier": "secondary", **selected["secondary"]}
        set_phase(plan, st, n, "in progress", note)
        print(f"phase start: {n} {ph['title']} in progress")
    return 0


def cmd_phase_report(plan, n, a):
    with writing(plan) as st:
        ph = phase_of(st, n)
        if ph["status"] != "in progress":
            raise Refuse("not-running", f"phase {n} is {ph['status']}", f"`pipeline.py phase start {plan} {n}` first")
        configured, outcomes = phase_checks(st), {}
        for command, outcome in a.check:
            if command not in configured or command in outcomes:
                raise Refuse("bad-phase-check", f"{command!r} is not a distinct configured phase check", "give each configured command once; use --checks for additional checks")
            outcome = outcome.strip()
            if outcome != "passed" and not (outcome.startswith("failed:") and outcome[7:].strip()):
                raise Refuse("bad-phase-outcome", f"{command!r} has no meaningful outcome", "use `passed` or `failed: REASON`")
            outcomes[command] = outcome
        ph["report"] = {"at": now(), "became": a.became, "skills": a.skills, "interfaces": a.interfaces,
                        "checks": a.checks, "check_outcomes": outcomes, "commits": a.commit}
        print(f"phase report: {n} recorded, {len(a.commit)} commit(s)")
    return 0


def cmd_phase_done(plan, n, note):
    with writing(plan) as st:
        ph = phase_of(st, n)
        if ph["status"] != "in progress":
            raise Refuse("not-running", f"phase {n} is {ph['status']}", f"`pipeline.py phase start {plan} {n}` first")
        tree, bad = tree_of(plan, st), []
        rep, allowed = ph.get("report"), ph["territory"] + ph.get("grants", [])
        g = lambda *a: git(*a, check=False, cwd=tree)
        if not rep:
            bad.append(("no-report", f"phase {n} has no recorded report", f"`pipeline.py phase report {plan} {n} --became … --commit <sha>`"))
        else:
            if missing := missing_phase_checks(st, rep):
                bad.append(("phase-checks-missing", f"phase {n} is missing outcomes for {', '.join(missing)}",
                            f"the implementer reissues `phase report {plan} {n}` with `--check COMMAND OUTCOME` for each configured check"))
            ref = st["branch"] if g("rev-parse", "--verify", "-q", f"refs/heads/{st['branch']}").returncode == 0 else "HEAD"
            for c in rep["commits"]:
                r = g("rev-parse", "--verify", "-q", f"{c}^{{commit}}")
                sha = r.stdout.strip()
                if r.returncode or g("merge-base", "--is-ancestor", sha, ref).returncode:
                    bad.append(("commit-missing", f"commit {c} is not on {ref}", "commit on the plan's branch in the plan's tree and report the SHA"))
                elif (old := g("merge-base", "--is-ancestor", sha, st["base"]).returncode) > 1:
                    bad.append(("bad-base", f"the plan's base {st['base']} is not a commit in {tree}", f"`pipeline.py plan base {plan} <ref>`"))
                elif sha == st["base"] or old == 0:
                    bad.append(("commit-old", f"commit {c} is not after the base {st['base'][:7]}", "report the phase's own commits"))
                else:
                    # a merge counts by what it brought into the branch: its diff against the first parent
                    parents = g("rev-list", "--parents", "-n", "1", sha).stdout.split()[1:]
                    paths = (g("diff", "--name-only", parents[0], sha) if len(parents) > 1
                             else g("diff-tree", "--no-commit-id", "--name-only", "-r", "--root", sha)).stdout.splitlines()
                    for f in paths:
                        if not inside(f, allowed):
                            bad.append(("outside-territory", f"commit {c[:7]} changed {f}, outside phase {n}'s territory and grants",
                                        f"`pipeline.py grant {plan} {n} {f}` if it is right, else undo it"))
        for l in g("status", "--porcelain", "--untracked-files=all", "--", *allowed).stdout.splitlines():
            bad.append(("uncommitted", f"{l[3:]} is " + ("staged" if l[0] not in " ?" else "uncommitted") + f" in phase {n}'s territory", "commit it or remove it"))
        if bad:
            r = Refuse(*bad[0])
            r.diags = bad
            raise r
        before = set(ready_phases(st))
        set_phase(plan, st, n, "done", note)
        new = sorted(set(ready_phases(st)) - before)
        print(f"phase done: {n} {ph['title']}\nready: {', '.join(map(str, new)) or 'none'}")
    head, tail = read_plan(plan_paths(plan)[0])
    show_next(summary(plan, st, head, tail, workflow=True)["workflow"]["actions"])
    return 0


def cmd_owner(plan, path):
    head, _ = read_plan(plan_paths(plan)[0])
    st = load_state(plan, required=True)
    tree = tree_of(plan, st)
    rel = os.path.relpath(path, tree) if os.path.isabs(path) else path
    ph = owner_of(st, rel)
    print(f"phase {ph['n']} ({ph['title']}) owns {rel}" if ph else f"none: no running phase owns {rel}")
    for _, m, f in drift_diags(plan, st, head):
        print(f"Drift: {m} — fix: {f}")
    return 0


def cmd_grant(plan, n, path, note):
    with writing(plan) as st:
        ph = phase_of(st, n)
        tree = os.path.realpath(tree_of(plan, st))
        full = os.path.realpath(path if os.path.isabs(path) else os.path.join(tree, path))
        path = os.path.relpath(full, tree)
        if path == ".." or path.startswith("../"):
            raise Refuse("outside-tree", f"{full} is outside the plan's tree {tree}", "grant a path inside the tree")
        other = owner_of(st, path, skip=n)
        if other:
            raise Refuse("owned", f"{path} belongs to running phase {other['n']} ({other['title']})",
                         "wait for that phase, or ask the orchestrator to change the plan")
        if path not in ph.setdefault("grants", []):
            ph["grants"].append(path)
        record(plan, st, f"grant phase {n}", None, path, note)
        print(f"grant: phase {n} may change {path}")
    return 0


def cmd_decision(plan, a):
    with writing(plan) as st:
        st.setdefault("decisions", []).append({"at": now(), "phase": a.phase, "by": a.by, "question": a.question, "source": a.source,
                                               "answer": a.answer, "why": a.why, "cost": a.cost})
        print(f"decision: recorded ({len(st['decisions'])})")
    return 0


def spec_entry_lines(md):
    """The plan's `## Spec` entries for an implementer's brief."""
    out, problems = [], []
    lines = read_plan(md)[0]
    secs = sections(lines)
    entries = parse_section(*secs["Spec"], problems) if "Spec" in secs else "none"
    if entries != "none":
        done = done_items(secs.get("Done", (0, []))[1])
        out += ["## Spec entries of the plan", "", "Each test that guards one carries its ID (`area#rule`) in its name or title.", ""]
        for e in entries:
            out.append(f"{e['sign']} {e['id']} — {e['statement'] or ''}".rstrip(" —"))
            if "Done" in e["keys"]:
                out += [f"  Done {x}: {done.get(x, '?')}" for x in cited(e, done, [])]
        out.append("")
    return out


def cmd_brief(plan, kind, n, note, cases=(), provider=None):
    md = plan_paths(plan)[0]
    lines, _ = read_plan(md)
    st = load_state(plan, required=True)
    root = plan_root(md)
    checked_plan(md, lines, root, check_references=False)
    history = plan_checkout(md)
    if (epic := st.get("epic")) and os.path.lexists(os.path.join(history, epic["path"])):
        check_epic(history, epic["path"], epic["row"])
    tree = tree_of(plan, st)
    drift = drift_diags(plan, st, lines)
    if drift and kind == "implementer":
        r = Refuse(*drift[0])
        r.diags = drift
        raise r
    require_consent(plan, st, head=lines)
    cli = shlex.join(cli_argv(md)) if standalone_bundle() is not None else f'python3 "{os.path.realpath(__file__)}"'
    shell_md = shlex.quote(md)
    head = git("rev-parse", "HEAD", check=False, cwd=tree).stdout.strip()
    review = review_target(st, cycle_of(st), tree, head) if kind == "reviewer" else None
    out = [f"# Brief: {kind} — {st['title']}", "",
           f"Plan: {md}", f"Tree: {tree}", f"CLI: {cli}",
           f"Branch: {st['branch']}", f"Base: {st['base']}", f"HEAD: {head}",
           "Rules: " + (", ".join(x for x in (os.path.join(tree, "docs", "spec"), os.path.join(tree, "AGENTS.md")) if os.path.exists(x)) or "none"), ""]
    package = PACKAGE
    role = "implementer" if kind in ("implementer", "fix", "round") else kind
    definition = role_definition(role)
    source = os.path.join(package, definition["roles"][role])
    out += [f"Role: {role}", f"Instructions: {cli} {role} --plan {shell_md}", f"Role source: {source}", f"Protocol: {os.path.join(package, 'references', 'SESSIONS.md')}",
            f"Assignment: {kind}" + (f" phase {n}" if n is not None else ""),
            "Return contact: dispatching build coordinator; use native messages or the agreed result/artifact channel.", "",
            "Initialization evidence: run the instructions command before work; return their loaded paths, brief path, "
            "requested/effective executor settings when exposed, cwd/branch, scope and reporting boundaries. "
            "Report a conflicting higher-priority instruction before acting.",
            "Continuation: retain this role, assignment, approved executor, tree, return contact and report commands. "
            "Read current CLI reports and Git facts before resuming; do not replay completed commands or duplicate reports. "
            "A replacement requires the old attempt and its write-capable jobs confirmed stopped; unknown or still-writing attempts block replacement. "
            "Only the coordinator advances phase/build/gate transitions; retain this role's prescribed reporting, verdict and land commands. Follow the protocol for questions, recovery and approval.", ""]
    for condition, dependency in definition.get("when", {}).items():
        if dependency["role"] == role:
            out.append(f"For {condition}: " + ", ".join(os.path.join(package, path) for path in dependency["inputs"]))
    assigned = phase_of(st, n).get("executor") if kind == "implementer" else None
    if assigned:
        if provider is not None and provider != assigned["provider"]:
            raise Refuse("build-assignment", f"phase {n} is assigned to {assigned['provider']}", "reuse the recorded executor")
        provider, selected, tier, profile = assigned["provider"], assigned, assigned["tier"], assigned
    elif provider is not None or (provider := st.get("build_provider")):
        selected = executor_selection(plan, provider)
        tier = brief_tier(kind, review[0] if review else None)
        profile = selected[tier]
    elif "executors" in st.get("run", {}):
        raise Refuse("provider-required", "a brief with executor presets requires --provider", "supply the current provider; no provider is inferred from a model")
    if provider is not None:
        out += [f"Executor provider: {provider}", f"Executor source: {selected['source']}", f"Executor tier: {tier}",
                f"Executor model: {profile['model']}"]
        if "effort" in profile:
            out.append(f"Executor effort: {profile['effort']}")
        out += ["Apply this model and effort explicitly; do not inherit another role preset.", ""]
    if kind == "implementer":
        ph = phase_of(st, n)
        if not (phase := phase_brief_text(lines, n)):
            raise Refuse("phase-text-gone", f"the plan file has no heading for phase {n}", f"run `pipeline.py approve {plan}` or restore the heading")
        sk = [phase_instruction(tree, x) for x in ph["skills"]]
        sp = [os.path.join(tree, x) for x in ph["spec"]]
        out += [*phase, f"Grants: {', '.join(ph.get('grants', [])) or 'none'}",
                f"Skills to read first: {', '.join(sk) or 'none'}", f"Spec area files: {', '.join(sp) or 'none'}", ""]
        out += ["## Checks for this phase", "", "Red before green. First show the public behaviour failing, then make it pass and run the affected fixtures.",
                "Run each configured phase check below for your territory. Report `--check 'COMMAND' passed` or `--check 'COMMAND' 'failed: REASON'` for each.",
                "Fix failures in your territory. For a failure outside it, name the path and failure in the outcome and proceed. Use `--checks` for fixture results and any other checks.", ""]
        out += [f"- `{command}`" for command in phase_checks(st)] or ["No configured phase checks."]
        out.append("")
        if "run" in st:
            v = fill(st["run"], st.get("alloc"))
            out += ["## The run", "", "[checks].phase = " + json.dumps(v["checks"]["phase"], ensure_ascii=False), ""]
            out += [f"{k} = {json.dumps(x, ensure_ascii=False)}" for k, x in v.get("run", {}).items()]
            out += [f"Drift: {m} — fix: {f}" for _, m, f in run_drift(plan, st)] + [""]
        out += spec_entry_lines(md)
        for w in ph["waits"]:
            r = phase_of(st, w)
            out += [f"## Phase {w} reported ({r['title']})", ""]
            if r.get("report"):
                x = r["report"]
                out += [f"Became true: {x['became']}", f"Skills: {x['skills']}", f"Interfaces: {x['interfaces']}",
                        f"Checks: {x['checks']}"]
                out += [f"- {command} — {outcome}" for command, outcome in x.get("check_outcomes", {}).items()]
                out += [f"Commits: {', '.join(x['commits'])}", ""]
            else:
                out += ["no report recorded", ""]
        out += ["## Record", "",
                f"- Your report: {cli} phase report {shell_md} {n} --became … --skills … --interfaces … --checks … --commit <sha> [--check COMMAND OUTCOME] (repeat --commit and --check)",
                f"- A ruling or product call: {cli} decision {shell_md} --phase {n} --by implementer --question … --from … --answer … --why … --cost …",
                f"- A path outside the territory you need: ask the orchestrator; it runs `{cli} grant {shell_md} {n} <path>`", ""]
        name = f"{plan_slug(st)}.brief-implementer-{n}.md"
    elif kind in ("reviewer", "verify", "fix"):
        if kind == "verify" and cases:
            with writing(plan) as w:
                c = cycle_of(w)
                assignment, fix = verify_target(c, tree)
                for case in cases:
                    done_text(w, case)
                if c["level"] != "small" and (fix or c["kind"] == "round"):
                    scopes = c.setdefault("verify_cases", {})
                    scopes[assignment] = sorted(set(scopes.get(assignment, [])) | set(cases))
                st = w
        body, name = brief_cycle(st, kind, cli, md, tree, cases, review)
        if kind == "verify" and task_for(plan):
            cmd_task_setup(plan, implicit=True)
        out += body + [f"Drift: {m} — fix: {f}" for _, m, f in drift]
    elif kind == "round":
        body, name = brief_round(plan, st, cli, md, tree)
        out += body + [f"Drift: {m} — fix: {f}" for _, m, f in drift]
    else:
        body, name = brief_judge(plan, st, cli, md, note)
        out += body + [f"Drift: {m} — fix: {f}" for _, m, f in drift]
        work = work_action("Judge", "", "judge", "judge")
        bind_assignment(md, st, "judge", work)
        out += ["", "## Record", ""]
        for report in work["assignment"]["reports"]:
            out.append("- " + shlex.join(report["argv"]) + " " + " ".join(report["options"].values()))
        last = (st.get("verdicts") or [{}])[-1]
        if last.get("kind") == "question" and note and last.get("answer") is None:
            with writing(plan) as w:
                w["verdicts"][-1]["answer"] = note
                st = w
    if standalone_bundle() is not None:
        binding = brief_binding(plan, st, kind, provider, phase=n, cases=cases, review=review)
        out += ["", f"Run release: {plan_release(plan) or 'unversioned run'}", f"Assignment binding: {binding}"]
    if task := task_for(plan, root):
        out += [f"Task artifacts: {task['artifacts']}"]
    out += ["## Orchestrator's note", "", note or "none", ""]
    path = os.path.join(os.path.dirname(md), name)
    k = 1
    while kind in ("reviewer", "verify") and os.path.exists(path):
        k += 1
        path = os.path.join(os.path.dirname(md), f"{name[:-3]}-{k}.md")
    open(path, "w", encoding="utf-8").write("\n".join(out))
    print(path)
    return 0


def level_of(st, tree):
    """-> (the gate's level, the changed paths that raised it): the plan's, normal when a path lies outside every territory and grant."""
    names = git("diff", "--name-only", f"{st['base']}..HEAD", check=False, cwd=tree).stdout.splitlines()
    allowed = [t for p in st["phases"] for t in p["territory"] + p.get("grants", [])]
    outside = sorted(f for f in names if not inside(f, allowed) and not inside(f, ["docs/spec"]))
    return ("normal" if outside else st["level"]), outside


def tree_snapshot(tree):
    g = lambda *a: git(*a, "--", ".", *NOT_MINE, check=False, cwd=tree).stdout
    return hashlib.sha256((g("status", "--porcelain", "--untracked-files=all") + g("diff", "HEAD")).encode()).hexdigest()


def checks_of(st):
    if "run" not in st:
        raise Refuse("no-run-values", "the plan has no approved run values", "write the run file and run `pipeline.py approve`")
    return fill(st["run"], st.get("alloc"))["checks"]["full"]


def check_host():
    """Identify the boot and PID namespace in which a process group can be probed."""
    try:
        if sys.platform == "darwin":
            boot = subprocess.check_output(["/usr/sbin/sysctl", "-n", "kern.bootsessionuuid"], text=True).strip()
            return f"{socket.gethostname()}:{boot}" if boot else None
        if sys.platform.startswith("linux"):
            with open("/proc/sys/kernel/random/boot_id", encoding="ascii") as f:
                return f"{socket.gethostname()}:{f.read().strip()}:{os.readlink('/proc/self/ns/pid')}"
    except (OSError, subprocess.SubprocessError):
        pass
    return None


def check_processes(pgid):
    lines = subprocess.check_output(["/bin/ps", "-ax", "-o", "pid=,pgid=,stat=,lstart="], text=True,
                                    env={**os.environ, "LC_ALL": "C", "TZ": "UTC"}).splitlines()
    for line in lines:
        pid, group, state, start = line.split(None, 3)
        if int(group) == pgid:
            yield int(pid), state, start


def child_state(child):
    pgid, started = child.get("pgid"), child.get("start")
    if type(pgid) is not int or pgid < 1 or not started:
        return "unknown"
    try:
        os.killpg(pgid, 0)
        members = list(check_processes(pgid))
        if not members:
            os.killpg(pgid, 0)
            return "unknown"
    except ProcessLookupError:
        return "stopped"
    except (OSError, ValueError, subprocess.SubprocessError):
        return "unknown"
    if any(pid == pgid and start != started for pid, _, start in members):
        return "unknown"
    return "running" if any(state[0] not in "ZX" for _, state, _ in members) else "stopped"


def check_lock_path(plan):
    return plan_paths(plan)[1] + ".checks.lock"


def pending_check(st):
    if pending := st.get("check_transition"):
        return pending
    for c in reversed(st.get("cycles", [])):
        if (r := selected_run(c)) and not r.get("done", True):
            return {"cycle": cycle_label(c), "coordinator_pid": r.get("pid")}
    return None


def check_ownership(plan, pending, *, claiming=False):
    if not claiming:
        try:
            with open(check_lock_path(plan), "rb") as lease:
                fcntl.flock(lease, fcntl.LOCK_SH | fcntl.LOCK_NB)
        except BlockingIOError:
            return "running", "a coordinator or its child holds the check lock"
        except FileNotFoundError:
            pass
        except OSError:
            return "unknown", f"cannot inspect {check_lock_path(plan)}"
    if "id" not in pending:
        return "unknown", f"incomplete check record (coordinator PID {pending.get('coordinator_pid') or 'unknown'}) lacks child ownership evidence"
    host = pending.get("host")
    if not host or host != check_host():
        return "unknown", f"the recorded process scope ({host or 'unknown'}) cannot be observed here"
    child = pending.get("child")
    if child:
        state = child_state(child)
        if state == "running":
            return state, f"check process group {child['pgid']} is still active"
        if state == "unknown":
            return state, f"cannot verify the recorded check process group {child.get('pgid', 'unknown')}"
    return "stopped", "the prior check work has stopped"


def check_status(plan, pending, *, claiming=False):
    command = pending.get("command", "the full check")
    label = f"`{command}` ({pending['cycle']})"
    state, reason = check_ownership(plan, pending, claiming=claiming)
    if state == "running":
        return "wait", "checks-running", f"{label}: {reason}", "wait for the coordinator and its check processes to stop"
    if state == "unknown":
        fix = ("inspect the original session and its child processes; resume the original coordinator if available"
               if "id" not in pending else "inspect the process group from the original host, boot and PID namespace")
        return "ask", "checks-owner-unknown", f"{label}: {reason}", fix
    return "run", "checks-unfinished", f"{label}: {reason}", f"run `{command} <plan>` to recover this transition"


def check_action(plan, pending):
    kind, _, message, fix = check_status(plan, pending)
    text = f"{message}. {fix[0].upper()}{fix[1:]}."
    check = {key: pending[key] for key in ("command", "cycle", "target") if key in pending}
    if kind == "run":
        return {**run_action(plan, "Coordinator", text, pending["command"], "--check-id", pending["id"]), "check": check}
    return workflow_action("Coordinator", kind, text, check=check,
                           **({"waiting_for": "full-checks"} if kind == "wait" else {"input": "check-ownership"}))


@contextlib.contextmanager
def check_lease(plan):
    path = check_lock_path(plan)
    with contextlib.ExitStack() as stack:
        try:
            lease = stack.enter_context(open(path, "ab"))
            fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            st = load_state(plan)
            if st and (pending := pending_check(st)):
                command = pending.get("command", "the full check")
                raise Refuse("checks-running", f"`{command}` ({pending['cycle']}) still holds the check lock",
                             "wait for the coordinator and its check processes to stop")
            raise Refuse("checks-running", "a full check transition holds the check lock", "wait and read status again")
        except OSError as error:
            raise Refuse("checks-owner-unknown", f"cannot claim {path}: {error.strerror}", "restore access to the check lock and read status again") from error
        yield lease.fileno()


def recover_check(plan, st, command, check_id):
    pending = pending_check(st)
    if check_id is not None and (not pending or pending.get("id") != check_id or pending.get("command") != command):
        raise Refuse("checks-recovery-stale", "this recovery no longer matches the pending check transition", "read status again")
    if pending:
        kind, code, message, fix = check_status(plan, pending, claiming=True)
        if kind != "run" or pending["command"] != command:
            raise Refuse(code, message, fix)
    return pending


def begin_run(plan, st, cycle, tree, command, pending, *, target=None, note=None):
    """Select the suite and persist its owning transition under the plan lock."""
    if pending and (pending["cycle"], pending["target"]) != (cycle_label(cycle), target):
        raise Refuse("checks-recovery-stale", "the original check transition's target changed", "restore the original transition and read status again")
    cmds = checks_of(st)
    spec, cycle["spec_refusal"] = commit_spec(plan, st, tree)
    head = head_sha(None, tree)
    st["check_transition"] = {"id": pending["id"] if pending else secrets.token_hex(16), "command": command,
                              "cycle": cycle_label(cycle), "target": target, "host": check_host(), "child": None, "note": note}
    keep = cycle["runs"] = [r for r in cycle["runs"] if r.get("done", True)]
    for i, r in enumerate(keep):
        if r["head"] == head and r["full"] == cmds:
            if i == len(keep) - 1:
                cycle.pop("current_run", None)
            else:
                cycle["current_run"] = i
            return r, True, spec
    run_ = {"at": now(), "head": head, "full": cmds, "commands": [], "done": not cmds}
    cycle["runs"].append(run_)
    cycle.pop("current_run", None)
    return run_, False, spec


CHECK_CHILD = """import os, signal, sys
fd = int(sys.argv[1])
start = os.read(fd, 1)
os.close(fd)
if start:
    for name in ('SIGPIPE', 'SIGXFZ', 'SIGXFSZ'):
        if sig := getattr(signal, name, None):
            signal.signal(sig, signal.SIG_DFL)
    os.execl('/bin/sh', '/bin/sh', '-c', sys.argv[2])
"""


def run_checks(plan, cycle, run_, tree, lease):
    """Run commands outside the plan lock with the process group recorded before each command starts."""
    task = task_for(plan)
    env = None
    if task and run_["full"]:
        cmd_task_setup(plan, implicit=True)
        env = task_env(task, plan_root(plan_paths(plan)[0]), load_state(plan, required=True).get("alloc", {}))
    for cmd in run_["full"]:
        reader, writer = os.pipe()
        process = None
        try:
            with os.fdopen(writer, "wb") as release, os.fdopen(reader, "rb") as start:
                with writing(plan) as st:
                    process = subprocess.Popen([sys.executable, "-I", "-S", "-c", CHECK_CHILD, str(reader), cmd], cwd=tree, start_new_session=True, env=env,
                                               pass_fds=(start.fileno(), lease), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, errors="replace")
                    try:
                        born = next(started for pid, _, started in check_processes(process.pid) if pid == process.pid)
                    except (StopIteration, OSError, ValueError, subprocess.SubprocessError) as error:
                        raise Refuse("checks-owner-unknown", f"cannot identify the new check process group {process.pid}",
                                     "restore local process inspection and read status again") from error
                    child = {"pgid": process.pid, "start": born}
                    st["check_transition"]["child"] = child
                before = tree_snapshot(tree)
                # EOF cancels the child if the coordinator dies before saving ownership.
                release.write(b"1")
        except BaseException:
            if process is not None:
                process.communicate()
            raise
        stdout, stderr = process.communicate()
        state = child_state(child)
        if state != "stopped":
            raise Refuse("checks-running" if state == "running" else "checks-owner-unknown",
                         f"check process group {process.pid} has no confirmed stop", "inspect the group, then read status again")
        changed = tree_snapshot(tree) != before
        res = {"command": cmd, "exit": process.returncode, "changed_tree": changed, "red": bool(process.returncode or changed)}
        if res["red"]:
            res["tail"] = "\n".join((stdout + stderr).rstrip().splitlines()[-20:])
        with writing(plan) as st:
            c = next(c for c in st["cycles"] if cycle_label(c) == cycle_label(cycle))
            run_ = selected_run(c)
            run_["commands"].append(res)
            run_["done"] = len(run_["commands"]) == len(run_["full"])
            st["check_transition"]["child"] = None
    return run_


def selected_run(c):
    return c["runs"][c.get("current_run", -1)] if c["runs"] else None


def settled(plan, st):
    if pending := pending_check(st):
        _, code, message, fix = check_status(plan, pending)
        raise Refuse(code, message, fix)


def close_check(plan, st, transition, run_, tree):
    current = st.get("check_transition")
    if not current or current["id"] != transition["id"]:
        raise Refuse("checks-recovery-stale", "the original check transition is no longer pending", "read status again")
    on_branch(st, tree)
    if tree_of(plan, st) != tree or run_["head"] != head_sha(None, tree) or run_["full"] != checks_of(st):
        raise Refuse("checks-stale", "HEAD or the approved commands changed during the full checks",
                     f"run `{transition['command']} <plan>` again")
    del st["check_transition"]


def checks_current(st, c, tree):
    r = selected_run(c)
    current = tree_id(tree, "HEAD")
    return bool(current and r and r.get("done", True) and r["full"] == checks_of(st) and current == tree_id(tree, r["head"]))


def require_current_checks(plan, st, c):
    settled(plan, st)
    if st.get("rounds") and not st["rounds"][-1]["done"]:
        raise Refuse("round-open", "a round is still running", "finish its report and re-check")
    if c["fixes"] and not c["fixes"][-1]["done"]:
        raise Refuse("fix-open", "a fix is still running", "finish its report and re-check")
    tree = tree_of(plan, st)
    if not checks_current(st, c, tree):
        fix = "run `gate start` again" if c["kind"] == "gate" else "restore the checked round tree or obtain authorization for another round"
        raise Refuse("checks-stale", "the newest cycle has no current full check run", fix)
    return tree


def show_run(r, reused):
    green = not any(c["red"] for c in r["commands"])
    state = "green" if green else "red"
    if not r.get("done", True):
        state = f"unfinished, {len(r['commands'])} of {len(r['full'])} ran"
    out = [f"checks at {r['head'][:7]}: " + state + (f" (reused, run {r['at']})" if reused else f" (run {r['at']})")]
    for c in r["commands"]:
        why = ", changed the tree" if c["changed_tree"] else ""
        out.append(f"  {'red' if c['red'] else 'ok '}  {c['command']} — exit {c['exit']}{why}")
        out += [f"        {l}" for l in c.get("tail", "").splitlines()]
    return out


def commit_spec(plan, st, tree):
    """Write the rules with `spec write`, commit docs/spec/ alone; -> (lines for the report, the refusal's lines or None)."""
    md, buf = plan_paths(plan)[0], io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = run("write", md, None, cwd=tree)
    lines = buf.getvalue().splitlines()
    if rc:
        if any("commits after the base" in l for l in lines):
            # a docs/spec/ commit another branch holds came with the default branch, not from a hand edit on this one
            shas = git("log", "--format=%H", f"{st['base']}..HEAD", "--", "docs/spec", check=False, cwd=tree).stdout.split()
            held = {b.strip(" *+") for c in shas for b in git("branch", "--format=%(refname:short)", "--contains", c, check=False, cwd=tree).stdout.split()}
            if held - {st["branch"]}:
                raise Refuse("stale-base", " ".join(lines), "the orchestrator moves the base: `pipeline.py plan base <plan> $(git merge-base <default> HEAD)`, then `gate start` again; not a fix's item")
        if any("docs/spec/" in l for l in lines):
            return ["spec write refused:"] + [f"  {l}" for l in lines], lines
        fix = "fix the plan's `## Spec` or its base"
        raise refuse_all([("spec-refused", l, fix) for l in lines] or [("spec-refused", "spec write failed", fix)])
    g = lambda *a: git(*a, check=False, cwd=tree)
    g("add", "-A", "--", "docs/spec")
    if g("diff", "--cached", "--quiet", "--", "docs/spec").returncode == 0:
        return ["spec: nothing to commit"], None
    r = g("commit", "-q", "-m", f"docs(spec): write the rules for {plan_slug(st)}", "--", "docs/spec")
    if r.returncode:
        raise Refuse("git-failed", r.stderr.strip() or r.stdout.strip(), "fix the tree and run it again")
    return [f"spec: committed docs/spec/ at {head_sha(md, tree)[:7]}"], None


def cmd_gate_start(plan, note, lease, check_id):
    with writing(plan) as st:
        pending = recover_check(plan, st, "gate start", check_id)
        if pending:
            note = pending.get("note")
        require_consent(plan, st)
        open_ = [p["n"] for p in st["phases"] if p["status"] != "done"]
        if open_ and not note:
            raise Refuse("phases-open", f"phase {', '.join(map(str, open_))} is not done", "finish them, or pass --note with the reason to open the gate now")
        tree = tree_of(plan, st)
        on_branch(st, tree)
        cycles = st.setdefault("cycles", [])
        cycle = next((c for c in cycles if c["kind"] == "gate"), None)
        if cycle is None:
            cycle = {"kind": "gate", "n": 1, "at": now(), "level": None, "raised_by": [], "spec_refusal": None,
                     "runs": [], "findings": [], "results": [], "fixes": []}
            cycles.append(cycle)
            record(plan, st, "gate", None, "opened", note)
        r, reused, out = begin_run(plan, st, cycle, tree, "gate start", pending, note=note)
        cycle["level"], cycle["raised_by"] = level_of(st, tree)
        transition = st["check_transition"]
        head = f"gate: {plan_slug(st)} level {cycle['level']}" + (f", raised by {', '.join(cycle['raised_by'])}" if cycle["raised_by"] else "")
    if not reused:
        r = run_checks(plan, cycle, r, tree, lease)
    with writing(plan) as st:
        close_check(plan, st, transition, r, tree)
    print(head)
    print("\n".join(out + show_run(r, reused)))
    return 0


FIXES_PER_CYCLE = 2
FINDING_KINDS = {"defect": "D", "convention": "C", "observation": "O", "unjudged": "U"}
LISTS = [("defect", "Defects"), ("convention", "Conventions"), ("observation", "Observations"), ("unjudged", "Could not be judged")]


def cycle_of(st):
    """The cycle records go to: the newest one."""
    if not st.get("cycles"):
        raise Refuse("no-cycle", "no check cycle is open", "run `pipeline.py gate start` first")
    return st["cycles"][-1]


def cycle_label(c):
    return "gate" if c["kind"] == "gate" else f"{c['kind']}-{c['n']}"


def last_finished_fix(c):
    return next((f for f in reversed(c["fixes"]) if f["done"]), None)


def fix_assignment(c, fix):
    return f"{cycle_label(c)}-fix-{fix['n']}"


def verify_target(c, tree, head="HEAD"):
    last = last_finished_fix(c)
    if last and (current := tree_id(tree, head)) and tree_id(tree, last["done"]["head"]) == current:
        return fix_assignment(c, last), last
    return cycle_label(c), None


def same_tree_land(st, c, tree, land, head):
    return (head == land["tip"] and not land["difference"]
            and any(v["n"] == land.get("judge") and v["cycle"] == cycle_label(c) for v in st.get("verdicts", []))
            and (current := tree_id(tree, head)) and current == tree_id(tree, land["pre"]))


def baseline_review_target(st, c, head):
    return cycle_label(c) + "-baseline", f"{st['base']}..{head}", None


def review_target(st, c, tree, head, *, historical=False):
    lands = st.get("lands", [])
    if lands and head == lands[-1]["tip"]:
        # Only the recorded land rewrite can carry a review across commits.
        for land in reversed(lands):
            if same_tree_land(st, c, tree, land, head):
                head = land["pre"]
    label = cycle_label(c)
    start = st["rounds"][c["n"] - 1]["from"] if c["kind"] == "round" else st["base"]
    if c["kind"] == "round":
        baseline = baseline_review_target(st, c, head)
        last_review = (c.get("reviews") or [{}])[-1]
        if (last_review.get("assignment"), last_review.get("range")) == baseline[:2] or (
                not historical and baseline_evidence(st, c, tree)[0]):
            return baseline
    last = last_finished_fix(c)
    if last and head == last["done"]["head"]:
        # A fix-only review needs a completed chain from the start of this cycle.
        covered = set()
        for review in c.get("reviews", []):
            lower, _, upper = review["range"].partition("..")
            if (review["assignment"] == label and lower == start) or lower in covered:
                covered.add(upper)
        if last["from"] in covered:
            return fix_assignment(c, last), f"{last['from']}..{head}", last
    return label, f"{start}..{head}", None


def review_is_current(c, target):
    last = (c.get("reviews") or [{}])[-1]
    return (last.get("assignment"), last.get("range"), last.get("findings")) == (*target[:2], len(c["findings"]))


def require_review(c, target):
    if not review_is_current(c, target):
        issue = "stale" if c.get("reviews") else "unrecorded"
        raise Refuse("review-missing", f"review completion is {issue} for {target[0]} ({target[1]})",
                     "the reviewer uses `brief reviewer` and records `review complete`")


def require_review_target(plan, st, c, a):
    tree = require_current_checks(plan, st, c)
    target = review_target(st, c, tree, head_sha(None, tree))
    if (a.assignment, a.range) != target[:2]:
        raise Refuse("review-target", f"the assigned range is {target[1]} for {target[0]}", "use `brief reviewer` for the current assignment")
    return target


def cmd_review(plan, a):
    with writing(plan) as st:
        require_consent(plan, st)
        c = cycle_of(st)
        target = require_review_target(plan, st, c, a)
        owed = outstanding_evidence(st, c, tree_of(plan, st))
        if review_is_current(c, target) and not any(v["owed"] == "reviewer" for v, _ in owed):
            print(f"review: {target[0]} already complete")
        else:
            c.setdefault("reviews", []).append({"at": now(), "assignment": target[0], "range": target[1], "findings": len(c["findings"])})
            print(f"review: {target[0]} complete")
    return 0


def latest_results(c, start=0):
    return {r["case"]: r for r in c["results"][start:]}


def human_case(c, case):
    return c["level"] == "small" or case["you_check"]


def required_result_cases(st, c, tree, head="HEAD"):
    if c["level"] == "small":
        return set()
    assignment, fix = verify_target(c, tree, head)
    want = set(c.get("verify_cases", {}).get(assignment, []))
    if fix and "verify_cases" in fix:
        want.update(fix["verify_cases"])
    elif c["kind"] == "gate":
        want.update(d["n"] for d in st.get("done", []) if not human_case(c, d))
    elif fix:
        want.update(int(item.removeprefix("done-")) for item in fix["items"] if item.startswith("done-"))
    return want


def pending_results(st, c, tree, head="HEAD"):
    if not (want := required_result_cases(st, c, tree, head)):
        return []
    current, results = tree_id(tree, head), latest_results(c)
    checked_trees = {commit: tree_id(tree, commit) for commit in {results[n]["commit"] for n in want if n in results and results[n].get("commit")}}
    return sorted(n for n in want if not current or n not in results or checked_trees.get(results[n].get("commit")) != current)


def verify_case_scope(st, c, tree, cases=(), *, recapture=False, head="HEAD"):
    if verify_target(c, tree, head)[1] or c["kind"] == "round":
        recheck = required_result_cases(st, c, tree, head) if recapture else pending_results(st, c, tree, head)
        failed = {n for n, r in latest_results(c).items() if r["outcome"] == "failed"}
        return set(cases) | set(recheck) | failed
    return set(cases) or {d["n"] for d in st.get("done", []) if not d["you_check"]}


def items(c):
    """The one list of a cycle, in this order: the rules' refusal, red checks, Defects, failed cases."""
    out = []
    if c.get("spec_refusal"):
        out.append({"id": "spec", "kind": "spec", "text": "spec write refused: " + "; ".join(c["spec_refusal"])})
    for i, x in enumerate((selected_run(c) or {}).get("commands", []), 1):
        if x["red"]:
            out.append({"id": f"check-{i}", "kind": "check", "text": f"{x['command']} — exit {x['exit']}" + (", changed the tree" if x["changed_tree"] else ""),
                        "tail": x.get("tail", "")})
    out += [{"id": f["id"], "kind": "defect", "where": f["where"], "text": f["text"], "source": f["source"]}
            for f in c["findings"] if f["kind"] == "defect" and not f.get("again")]
    out += [{"id": f"done-{n}", "kind": "case", "text": f"{r['do']} → {r['see']}: {r['detail']}", "capture": r["capture"]}
            for n, r in sorted(latest_results(c).items()) if r["outcome"] == "failed"]
    return out


def taken(c, i):
    return any(i in f["items"] for f in c["fixes"])


def fate(c, i):
    for f in c["fixes"]:
        if i in f["survived"]:
            return f"open, survived fix {f['n']}"
    f = next((f for f in c["fixes"] if i in f["items"]), None)
    return f"taken by fix {f['n']}" if f else "open"


def done_text(st, n):
    d = next((d for d in st.get("done", []) if d["n"] == n), None)
    if d is None:
        raise Refuse("no-case", f"the plan has no Done item {n}", "Done items: " + ", ".join(str(x["n"]) for x in st.get("done", [])) + "; run `pipeline.py approve` if the plan changed")
    return d["text"]


def cmd_finding(plan, a):
    if a.kind != "unjudged" and not a.where:
        raise Refuse("no-place", f"a {a.kind} needs --where file:line", "give the place, or record it as `--kind unjudged`")
    with writing(plan) as st:
        c = cycle_of(st)
        if a.assignment is not None or a.range is not None:
            require_review_target(plan, st, c, a)
        if a.again:
            f = next((f for f in c["fixes"] if f["done"] and a.again in f["items"] and a.again.startswith("D")), None)
            if f is None:
                raise Refuse("not-taken", f"{a.again} is not a Defect a finished fix took", "--again names a Defect from the fix just re-checked")
            if a.again not in f["survived"]:
                f["survived"].append(a.again)
        n = 1 + sum(x["kind"] == a.kind for x in c["findings"])
        fid = f"{FINDING_KINDS[a.kind]}{n}"
        c["findings"].append({"id": fid, "at": now(), "kind": a.kind, "where": a.where, "source": a.source, "text": a.text, "again": a.again})
        print(f"finding: {fid} recorded" + (f", {a.again} found again" if a.again else ""))
    return 0


def cmd_result(plan, a):
    with writing(plan) as st:
        c = cycle_of(st)
        text = done_text(st, a.case)
        tree = tree_of(plan, st)
        head = head_sha(plan_paths(plan)[0], tree)
        if a.cycle is not None or a.head is not None:
            assigned = git("rev-parse", "--verify", "--end-of-options", f"{a.head}^{{commit}}", check=False, cwd=tree).stdout.strip() if a.head else None
            if a.cycle != cycle_label(c) or not assigned or tree_id(tree, assigned) != tree_id(tree, head):
                raise Refuse("result-target", "the use case was assigned in a different cycle or on a different tree", "use `brief verify` to drive the case on the current tree")
            head = assigned
        do, _, see = text.partition(" → ")
        if a.outcome != "not-reached" and not a.capture:
            raise Refuse("no-capture", f"a {a.outcome} result has no capture", "pass --capture with the screenshot path or the command's output")
        if a.outcome != "passed" and not a.detail:
            raise Refuse("no-detail", f"a {a.outcome} result has no detail", "pass --detail: what was seen, or what is needed")
        c["results"].append({"at": now(), "case": a.case, "do": a.do or do, "see": a.see or see, "width": a.width or "-",
                             "outcome": a.outcome.replace("-", " "), "detail": a.detail, "capture": a.capture,
                             "commit": head})
        if a.outcome == "failed":
            i = f"done-{a.case}"
            f = next((f for f in c["fixes"] if f["done"] and i in f["items"]), None)
            if f and i not in f["survived"]:
                f["survived"].append(i)
        print(f"result: case {a.case} {a.outcome}")
    return 0


def open_fix(c):
    f = c["fixes"][-1] if c["fixes"] else None
    if f is None or f["done"]:
        raise Refuse("no-fix", "no fix is running", "`pipeline.py fix start` first")
    return f


def cmd_fix(plan, a):
    with writing(plan) as st:
        c = cycle_of(st)
        tree = tree_of(plan, st)
        md = plan_paths(plan)[0]
        if a.command == "start":
            settled(plan, st)
            if c["fixes"] and not c["fixes"][-1]["done"]:
                raise Refuse("fix-open", f"fix {len(c['fixes'])} is running", "finish it with `fix report` and `fix done`")
            if len(c["fixes"]) >= FIXES_PER_CYCLE:
                raise Refuse("fixes-spent", f"this cycle's {len(c['fixes'])} fixes are spent", "what is open goes to the judge or the human")
            take = [i["id"] for i in items(c) if not taken(c, i["id"])]
            if not take:
                raise Refuse("nothing-open", "no open item for a fix",
                             "an item a fix took stays with it" if items(c) else "the one list is empty: skip `fix start`")
            recheck = set(pending_results(st, c, tree))
            recheck.update(n for n, r in latest_results(c).items() if r["outcome"] == "failed")
            c["fixes"].append({"n": len(c["fixes"]) + 1, "at": now(), "from": head_sha(md, tree), "items": take,
                               "report": None, "done": None, "survived": [], "verify_cases": sorted(recheck)})
            print(f"fix {len(c['fixes'])}: takes {', '.join(take)}")
            return 0
        f = open_fix(c)
        f["report"] = {"at": now(), "became": a.became, "skills": a.skills, "interfaces": a.interfaces, "checks": a.checks, "commits": a.commit}
        print(f"fix report: {f['n']} recorded, {len(a.commit)} commit(s)")
        return 0


def fix_done(plan, lease, check_id):
    with writing(plan) as st:
        pending = recover_check(plan, st, "fix done", check_id)
        require_consent(plan, st)
        c = cycle_of(st)
        tree = tree_of(plan, st)
        on_branch(st, tree)
        f = open_fix(c)
        report = f["report"]
        if not report:
            raise Refuse("no-report", f"fix {f['n']} has no report", "`pipeline.py fix report` first")
        gone = [x for x in report["commits"] if git("merge-base", "--is-ancestor", x, "HEAD", check=False, cwd=tree).returncode]
        if gone:
            raise Refuse("commit-gone", f"{', '.join(gone)} is not on the branch", "report the commits that are")
        r, reused, out = begin_run(plan, st, c, tree, "fix done", pending, target=f["n"])
        transition = st["check_transition"]
    if not reused:
        r = run_checks(plan, c, r, tree, lease)
    with writing(plan) as st:
        close_check(plan, st, transition, r, tree)
        c = cycle_of(st)
        if cycle_label(c) != transition["cycle"] or (f := open_fix(c))["n"] != transition["target"]:
            raise Refuse("checks-recovery-stale", "the original fix is no longer pending", "read status again")
        if f["report"] != report:
            raise Refuse("checks-report-changed", "the original fix report changed during the checks", "run `fix done <plan>` again")
        f["done"] = {"at": now(), "head": r["head"]}
        again = {i["id"] for i in items(c)}
        back = []
        for i in sorted(again):
            owner = next((g for g in reversed(c["fixes"]) if g["done"] and i in g["items"]), None)
            if owner and (i == "spec" or i.startswith("check-")) and i not in owner["survived"]:
                owner["survived"].append(i)
                back.append(i)
        print(f"fix {f['n']} done at {r['head'][:7]}" + (f", survived: {', '.join(f['survived'] + [i for i in back if i not in f['survived']])}" if f["survived"] or back else ""))
        print("\n".join(out + show_run(r, reused)))
    return 0


def entry_of(c, i):
    """The item or finding of cycle c with this id."""
    return next((x for x in items(c) if x["id"] == i), None) or next((f for f in c["findings"] if f["id"] == i), None)


def decisions(st):
    """(cycle label, id) -> (verdict, decision): the newest verdict that decided it."""
    return {(v["cycle"], d["id"]): (v, d) for v in st.get("verdicts", []) for d in v["decisions"]}


def closed_by(st, c, i):
    """What closed an entry of cycle c: 'round N' (a verdict's `round` decision the round took), 'fix N', or None."""
    v, d = decisions(st).get((cycle_label(c), i), (None, None))
    if d and d["action"] == "round" and v.get("round") is not None:
        return f"round {v['round']}"
    f = next((f for f in c["fixes"] if f["done"] and i in f["items"] and i not in f["survived"]), None)
    return f"fix {f['n']}" if f else None


def show_cycle(c, st=None):
    out = []
    if c.get("reviews"):
        review = c["reviews"][-1]
        out.append(f"Review complete ({review['findings']} findings in cycle): {review['assignment']} {review['range']}")
    for kind, title in LISTS:
        fs = [f for f in c["findings"] if f["kind"] == kind]
        if fs:
            out.append(f"{title}:")
            out += [f"  {f['id']} " + (f"{f['where']} — " if f["where"] else "") + f["text"] + (f" ({f['source']})" if f["source"] else "")
                    + (f" [{f['again']} again]" if f.get("again") else "") + (f" [closed by {by}]" if st and (by := closed_by(st, c, f["id"])) else "") for f in fs]
    if c["results"]:
        out.append("Results:")
        order = {"failed": 0, "not reached": 1, "passed": 2}
        for n, r in sorted(latest_results(c).items(), key=lambda x: (order[x[1]["outcome"]], x[0])):
            what = r["outcome"] + (f": {r['detail']}" if r["detail"] else "")
            out.append(f"  {n}. {r['do']} → {r['see']} — {r['width']} — {what} — {r['capture'] or '-'} — at {(r.get('commit') or '-')[:7]}")
    its = items(c)
    if its:
        out.append("One list:")
        out += [f"  {i['id']} ({fate(c, i['id'])}) " + (f"{i['where']} — " if i.get("where") else "") + i["text"] for i in its]
    for f in c["fixes"]:
        out.append(f"Fix {f['n']}: takes {', '.join(f['items'])}" + (f"; done at {f['done']['head'][:7]}" if f["done"] else "; running"))
        if f["report"]:
            out.append(f"  report: {f['report']['became']} (commits: {', '.join(x[:7] for x in f['report']['commits'])})")
    return out


AS_PRINTED = "Run each command below as printed, in full, never through a shell variable."


def brief_cycle(st, kind, cli, md, tree, cases, review):
    """The body and file name of a reviewer, verify or fix brief for the newest cycle."""
    shell_md = shlex.quote(md)
    c = cycle_of(st)
    if kind != "verify":
        settled(md, st)
    label = cycle_label(c)
    done = [f for f in c["fixes"] if f["done"]]
    last = done[-1] if done else None
    out, name = [], f"{plan_slug(st)}.brief-{kind}-{label}" + (f"-fix-{last['n']}" if last and kind != "fix" else "") + ".md"
    if kind == "reviewer":
        assignment, range_, last = review
        name = f"{plan_slug(st)}.brief-reviewer-{assignment}.md"
        if last:
            commits = git("rev-list", "--reverse", range_, cwd=tree).stdout.split()
            out += ([f"Range: {range_} (fix {last['n']}'s commits; a re-check reads only these)", "Commits: " + ", ".join(x[:7] for x in commits)]
                    if commits else [f"Range: none (fix {last['n']} made no commit)"])
            out += ["Items the fix took:"] + [f"- {i['id']} {i.get('where', '')} {i['text']}".replace("  ", " ") for i in items_of(c, last["items"])]
        elif c["kind"] == "round":
            has_commits = git("rev-list", "-1", range_, cwd=tree).stdout
            if assignment.endswith("-baseline"):
                out += [f"Range: {range_} (the full current baseline, to recover missing earlier evidence)"]
            else:
                out += [f"Range: {range_} (the round's commits)" if has_commits else f"Range: none (round {c['n']} made no commit)"]
            out += [f"Level: {c['level']}"]
        else:
            out += [f"Range: {range_}", f"Level: {c['level']}"]
        if run_ := selected_run(c):
            out += [""] + show_run(run_, True)
        bind = f"--assignment {assignment} --range {range_}"
        out += ["", "## Record", "", AS_PRINTED, "",
                f"- Each finding: {cli} finding {shell_md} --kind defect|convention|observation {bind} --where <file:line> --source <rule or plan line> --text …",
                f"- What you could not judge, only when there is one (with none, record nothing): {cli} finding {shell_md} --kind unjudged {bind} --text <what and why>"]
        if last:
            out += [f"- A Defect the fix took, found again: add --again <its ID>"]
        out += [f"- Complete the review: {cli} review complete {shell_md} {bind}", "",
                "Record completion after all findings, including when the review is clean or the assigned range is empty. Return one line.", ""]
    elif kind == "verify":
        owed_cases = {n for _, cases in outstanding_evidence(st, c, tree) for n in cases}
        baseline = baseline_evidence(st, c, tree)[1]
        baseline -= captured_cases(baseline, latest_results(c), tree, "HEAD")
        want = sorted(verify_case_scope(st, c, tree, set(cases) | owed_cases | baseline))
        bind = f"--cycle {label} --head {head_sha(md, tree)}"
        out += ["## Cases to drive", ""]
        out += [f"{n}. {done_text(st, n)}" for n in want] or ["no case to drive"]
        out += ["", f"How to run the system: {cli} run show {shell_md}", "", "Run each case's command exactly as written, one shell call per case.", "", "## Record", "", AS_PRINTED, "",
                f"- Each case: {cli} result {shell_md} --case <n> {bind} --outcome passed|failed|not-reached --capture <path or output> [--detail <what was seen, or why not reached>] [--width <w>]", ""]
    else:
        f = c["fixes"][-1] if c["fixes"] else None
        if f is None or f["done"]:
            raise Refuse("no-fix", "no fix is running", "`pipeline.py fix start` first")
        sk = sorted({x for p in st["phases"] for x in p["skills"] if x != "none"})
        out += [f"## Fix {f['n']} takes", ""]
        for i in items_of(c, f["items"]):
            capture = i.get("capture")
            out.append(f"- {i['id']} " + (f"{i['where']} — " if i.get("where") else "") + i["text"] + (f" (capture: {capture})" if capture else ""))
            out += [f"    {l}" for l in i.get("tail", "").splitlines()]
        out += ["", "Skills to read first: " + (", ".join(phase_instruction(tree, x) for x in sk) or "none"), ""] + spec_entry_lines(md) + ["## Record", "", AS_PRINTED, "",
                f"- Your report: {cli} fix report {shell_md} --became … --skills … --interfaces … --checks … [--commit <sha>] (repeat --commit; none when the fix changed nothing)",
                f"- A ruling or product call: {cli} decision {shell_md} --by implementer --question … --from … --answer … --why … --cost …", ""]
        name = f"{plan_slug(st)}.brief-fix-{label}-{f['n']}.md"
    return out, name


def items_of(c, ids):
    have = {i["id"]: i for i in items(c)}
    return [have.get(i, {"id": i, "text": "(no longer listed)"}) for i in ids]


# -- the verdict, the notes and the rounds

JUDGE_ROUNDS = 3
CAUSES = ["bug", "off-plan", "proto-mismatch", "grill-miss", "proto-miss", "feel-ui", "code-taste", "task"]
ACTIONS = ["let-through", "round", "question"]
EVIDENCE_ROLES = ("reviewer", "verify")
SOURCE = re.compile(r"^(P\d+|missed)$")


def author_role(record):
    return "human" if record["by"] == "user" else record["by"]


def human_authored(record):
    return author_role(record) == "human"


def epoch(st):
    """How many rounds the human has started: each starts a new count of judge rounds."""
    return sum(human_authored(r) for r in st.get("rounds", []))


def open_notes(st):
    return [n for n in st.get("notes", []) if n["round"] is None and n["cause"] != "task"]


def round_cycle(st, n):
    return next((c for c in st["cycles"] if c["kind"] == "round" and c["n"] == n), None)


def e2e_text(st, n):
    c = round_cycle(st, n)
    groups = {}
    for k, r in sorted(latest_results(c).items()) if c else []:
        groups.setdefault(r["outcome"], []).append(str(k))
    return "; ".join(f"Done {', '.join(v)} {k}" for k, v in groups.items())


def note_line(st, nt):
    parts = [f"{nt['n']}. {nt['text']}", nt["cause"]]
    r = next((r for r in st.get("rounds", []) if r["n"] == nt["round"]), None)
    if r and r["done"]:
        parts += [nt["source"], ", ".join(f"`{x[:7]}`" for x in r["report"]["commits"])] + ([f"e2e: {e}"] if (e := e2e_text(st, r["n"])) else [])
    return " — ".join(parts)


def plain_title(st):
    return st["title"].removeprefix("Plan: ")


def render_notes(st):
    out = [f"# Notes: {plain_title(st)}", "", "## Open"] + [note_line(st, n) for n in open_notes(st)]
    for r in reversed(st.get("rounds", [])):
        cs = r["report"]["commits"] if r["report"] else []
        span = "" if not cs else f" · `{cs[0][:7]}`" if len(cs) == 1 else f" · `{cs[0][:7]}..{cs[-1][:7]}`"
        out += ["", f"## Round {r['n']}{span}"] + ([f"Conflict at finish: {r['conflict']}"] if r.get("conflict") else []) + [note_line(st, n) for n in st["notes"] if n["round"] == r["n"]]
    tasks = [n for n in st.get("notes", []) if n["cause"] == "task"]
    if tasks:
        out += ["", "## Tasks"] + [note_line(st, n) for n in tasks]
    return "\n".join(out) + "\n"


def write_notes(plan, st):
    path = os.path.join(os.path.dirname(plan_paths(plan)[0]), plan_slug(st) + ".notes.md")
    if st.get("notes") or os.path.exists(path):
        open(path, "w", encoding="utf-8").write(render_notes(st))


def cmd_note(plan, a):
    with writing(plan) as st:
        ns = st.setdefault("notes", [])
        if a.command == "add":
            n = 1 + max([x["n"] for x in ns], default=0)
            ns.append({"n": n, "text": a.text, "cause": a.cause, "by": "human", "source": None, "round": None, "verdict": None})
            print(f"note {n}: recorded")
        else:
            nt = next((x for x in ns if x["n"] == a.n), None)
            if nt is None:
                raise Refuse("no-note", f"there is no note {a.n}", "notes: " + ", ".join(str(x["n"]) for x in ns))
            if a.command == "edit" and a.source is not None:
                if not human_authored(nt) or not SOURCE.match(a.source):
                    raise Refuse("bad-source", f"note {a.n} takes no source {a.source!r}", "a human's note is P<n>, a note the judge predicted, or missed; the judge's notes are marked by code")
                nt["source"] = a.source
            if (a.command == "drop" or a.text or a.cause) and (nt["round"] is not None or not human_authored(nt)):
                raise Refuse("note-fixed", f"note {a.n} is a judge's note or already in a round", "only an open note of the human's changes")
            if a.command == "drop":
                ns.remove(nt)
            else:
                nt["text"], nt["cause"] = a.text or nt["text"], a.cause or nt["cause"]
            print(f"note {a.n}: {'dropped' if a.command == 'drop' else 'changed'}")
        write_notes(plan, st)
    return 0


def pending_rounds(st):
    """The latest verdicts in a row that each ordered a round that has not started."""
    out = []
    for v in reversed(st.get("verdicts", [])):
        if v["kind"] != "round" or v.get("stop") or v.get("round") is not None:
            break
        out.insert(0, v)
    return out


def cmd_round(plan, a):
    with writing(plan) as st:
        rs, md, tree = st.setdefault("rounds", []), plan_paths(plan)[0], tree_of(plan, st)
        if a.command == "start":
            settled(plan, st)
            if rs and not rs[-1]["done"]:
                raise Refuse("round-open", f"round {rs[-1]['n']} is running", "finish it with `round report` and `round done`")
            gate = next((c for c in st.get("cycles", []) if c["kind"] == "gate"), None)
            if gate is None:
                raise Refuse("no-cycle", "the gate was never opened", "run `pipeline.py gate start` first")
            vs = [] if a.conflict else pending_rounds(st)
            take = [] if a.conflict else [n for n in st["notes"] if n["verdict"] in {v["n"] for v in vs}] if vs else open_notes(st)
            if not take and not a.conflict:
                raise Refuse("nothing-open", "no open note for a round", "record the human's notes with `pipeline.py note add`")
            if awaiting_first_verdict(st):
                outgoing = cycle_of(st)
                try:
                    require_evidence(st, outgoing, require_current_checks(plan, st, outgoing), None)
                except Refuse as error:
                    raise refuse_all([(code, f"cannot leave {cycle_label(outgoing)} before the first verdict: {message}", fix)
                                      for code, message, fix in error.diags]) from None
            if a.conflict and st["status"] == "passed":
                set_plan(plan, st, status="building", note=f"conflict at finish: {a.conflict}")
            r = {"n": len(rs) + 1, "at": now(), "by": "judge" if vs else "human", "from": head_sha(md, tree), "notes": [n["n"] for n in take], "report": None, "done": None}
            if a.conflict:
                r["conflict"] = a.conflict
            rs.append(r)
            st["cycles"].append({"kind": "round", "n": r["n"], "at": now(), "level": gate["level"], "raised_by": [], "spec_refusal": None,
                                 "runs": [], "findings": [], "results": [], "fixes": []})
            for n in take:
                n["round"] = r["n"]
            for v in vs:
                v["round"] = r["n"]
            write_notes(plan, st)
            print(f"round {r['n']} ({author_role(r)}): " + (f"conflict at finish: {a.conflict}" if a.conflict else f"takes notes {', '.join(map(str, r['notes']))}"))
            return 0
        r = rs[-1] if rs and not rs[-1]["done"] else None
        if r is None:
            raise Refuse("no-round", "no round is running", "`pipeline.py round start` first")
        r["report"] = {"at": now(), "became": a.became, "skills": a.skills, "interfaces": a.interfaces, "checks": a.checks, "commits": a.commit}
        print(f"round report: {r['n']} recorded, {len(a.commit)} commit(s)")
        write_notes(plan, st)
    return 0


def missing_note_sources(st, round_):
    return [n["n"] for n in st["notes"] if n["round"] == round_["n"] and n["source"] is None and human_authored(n)]


def round_done(plan, lease, check_id):
    with writing(plan) as st:
        pending = recover_check(plan, st, "round done", check_id)
        require_consent(plan, st)
        rs, tree = st.get("rounds", []), tree_of(plan, st)
        on_branch(st, tree)
        r = rs[-1] if rs and not rs[-1]["done"] else None
        if r is None:
            raise Refuse("no-round", "no round is running", "`pipeline.py round start` first")
        report = r["report"]
        if not report:
            raise Refuse("no-report", f"round {r['n']} has no report", "`pipeline.py round report` first")
        gone = [x for x in report["commits"] if git("merge-base", "--is-ancestor", x, "HEAD", check=False, cwd=tree).returncode]
        if gone:
            raise Refuse("commit-gone", f"{', '.join(gone)} is not on the branch", "report the commits that are")
        bare = missing_note_sources(st, r)
        if bare:
            raise Refuse("no-source", f"note {', '.join(map(str, bare))} has no source", "`pipeline.py note edit N --source P<n>|missed`")
        c = round_cycle(st, r["n"])
        run_, reused, out = begin_run(plan, st, c, tree, "round done", pending, target=r["n"])
        transition = st["check_transition"]
    if not reused:
        run_ = run_checks(plan, c, run_, tree, lease)
    with writing(plan) as st:
        close_check(plan, st, transition, run_, tree)
        r = st["rounds"][-1]
        if r["n"] != transition["target"] or r["done"]:
            raise Refuse("checks-recovery-stale", "the original round is no longer pending", "read status again")
        if r["report"] != report:
            raise Refuse("checks-report-changed", "the original round report changed during the checks", "run `round done <plan>` again")
        r["done"] = {"at": now(), "head": run_["head"]}
        for n in st["notes"]:
            if n["round"] == r["n"] and n["by"] == "judge":
                n["source"] = "judge"
        write_notes(plan, st)
        print(f"round {r['n']} done at {run_['head'][:7]}")
        print("\n".join(out + show_run(run_, reused)))
    return 0


def stop_reason(st):
    """Why a judge round must not open now, or None; the cap and the early-stop signs."""
    ep = epoch(st)
    rv = [v for v in st.get("verdicts", []) if v["kind"] == "round" and not v.get("stop") and v["epoch"] == ep]
    if len(rv) >= JUDGE_ROUNDS:
        return "judge rounds are past the cap"
    return None


def converging_stop(st, new):
    """The early-stop signs; `new` is how many notes the verdict in hand orders."""
    ep = epoch(st)
    rv = [len(v["notes"]) for v in st.get("verdicts", []) if v["kind"] == "round" and not v.get("stop") and v["epoch"] == ep]
    if len(rv) >= 2 and new >= rv[-1] >= rv[-2]:
        return "rounds stopped converging: two in a row left no fewer new notes than they took"
    mine = [i for i, c in enumerate(st["cycles"]) if c["kind"] == "round" and human_authored(st["rounds"][c["n"] - 1])]
    seen = {}
    for c in st["cycles"][mine[-1]:] if mine else st["cycles"]:
        for run_ in c["runs"]:
            for x in run_["commands"]:
                s = seen.setdefault(x["command"], [])
                if not s or s[-1] != x["red"]:
                    s.append(x["red"])
    for cmd, s in seen.items():
        if any(s[i:i + 3] == [True, False, True] for i in range(len(s))):
            return f"a check fixed before is red again: {cmd}"
    c = st["cycles"][-1]
    stand = [i["id"] for i in items(c) if i["kind"] == "defect" and fate(c, i["id"]).startswith("open")]
    if len(c["fixes"]) >= FIXES_PER_CYCLE and c["fixes"][-1]["done"] and stand:
        return f"the cycle's fixes are spent and a Defect stands: {', '.join(stand)}"
    return None


def render_judge(st, v, a):
    body = [v["report"]] + ([f"Evidence exception: {v['evidence_note']}"] if v.get("evidence_note") else []) + [f"Round: {t} — {c}" for t, c in a.note or []] + ([f"Question: {v['question']}"] if v["question"] else [])
    pred = [f"Human's verdict: {a.predicted}"] + [f"P{i}. {t} — {c}" for i, (t, c) in enumerate(a.predict or [], 1)]
    return (f"# Judge: {plain_title(st)}\n\nPlan: `{plan_slug(st)}` · head `{v['head'][:7]}` · {v['at']} · engine {a.engine}\n\n"
            "## Verdict\n" + "\n".join(body) + "\n\n## Prediction\n" + "\n".join(pred) + "\n")


def check_judge_file(path, *, optional=False):
    fix = "restore the Judge file written by the first verdict, including its Prediction"
    text = read_required(path, "no-verdict", fix, optional=optional)
    if text is None:
        return False
    if (not text.startswith("# Judge: ") or "\n## Verdict\n" not in text
            or not re.search(r"(?m)^## Prediction\n(?:Human|User)'s verdict: (pass|round)$", text)):
        raise Refuse("bad-verdict-file", f"{path} needs the Judge heading, Verdict and Prediction", fix)
    return True


def round_notes_file(md, st, round_):
    path = os.path.join(os.path.dirname(md), plan_slug(st) + ".notes.md")
    fix = "restore the generated notes file or reissue `round report` to render the notes again"
    text = read_required(path, "bad-notes-file", fix, optional=not round_["notes"])
    if text is None:
        return []
    if not text.startswith("# Notes: ") or not re.search(rf"(?m)^## Round {round_['n']}(?: · .+)?$", text):
        raise Refuse("bad-notes-file", f"{path} needs the Notes heading and a section for round {round_['n']}", fix)
    return [f"Notes file: {path}"]


def require_evidence(st, c, tree, note):
    baseline, cases, baseline_owed = baseline_evidence(st, c, tree)
    target = review_target(st, c, tree, head_sha(None, tree))
    if baseline and not review_is_current(c, target):
        raise Refuse("review-missing", f"earlier evidence is incomplete for {', '.join(baseline)}",
                     "the reviewer uses `brief reviewer` for the full current baseline and records `review complete`")
    require_review(c, target)
    owed = outstanding_evidence(st, c, tree) + baseline_owed
    if review := next((v for v, _ in owed if v["owed"] == "reviewer"), None):
        raise Refuse("review-missing", f"the judge requested a new review: {review['report']}",
                     "the reviewer uses `brief reviewer` and records `review complete`")
    cases -= captured_cases(cases, latest_results(c), tree, "HEAD")
    left = sorted(set(pending_results(st, c, tree)) | cases | {n for _, missing in owed for n in missing})
    if (left or owed) and not (note or "").strip():
        exception = "the judge names the reason with `verdict --evidence-note TEXT`"
        if left:
            raise Refuse("result-missing", f"Done {', '.join(map(str, left))} lacks current E2E evidence at level {c['level']}",
                         "Verify drives the cases from `brief verify`, or " + exception)
        raise Refuse("result-missing", "the Verify request has no assigned Done cases", exception)
    return owed


def requested_result_cases(st, c, tree, report, head="HEAD"):
    named = set(re.findall(r"\bDone\s+(\d+)\b", report, re.IGNORECASE))
    return {d["n"] for d in st.get("done", []) if str(d["n"]) in named} or verify_case_scope(st, c, tree, recapture=True, head=head)


def captured_cases(cases, results, tree, head, after=""):
    current = tree_id(tree, head) if cases and results else None
    return {n for n in cases if (r := results.get(n)) and r["at"] > after and r.get("capture")
            and current and r.get("commit") and tree_id(tree, r["commit"]) == current}


def outstanding_evidence(st, c, tree, head=None):
    requests = []
    label = cycle_label(c)
    for v in st.get("verdicts", []):
        if v["cycle"] != label:
            continue
        if v["kind"] == "evidence-owed":
            requests.append(v)
        elif (v.get("evidence_note") or "").strip():
            requests = [r for r in requests if r["owed"] != "verify"]
    owed = []
    for v in requests:
        if v["owed"] == "reviewer":
            reviews = c.get("reviews", [])
            recorded = len(reviews) > v["review_count"] if "review_count" in v else reviews and reviews[-1]["at"] > v["at"]
            if not recorded or not review_is_current(c, review_target(st, c, tree, head or head_sha(None, tree), historical=head is not None)):
                owed.append((v, []))
            continue
        cases = v.get("owed_cases") or requested_result_cases(st, c, tree, v["report"], head or "HEAD")
        results = latest_results(c, v.get("result_count", 0))
        captured = captured_cases(cases, results, tree, head or "HEAD", "" if "result_count" in v else v["at"])
        missing = sorted(set(cases) - captured)
        if missing or not cases:
            owed.append((v, missing))
    return owed


def baseline_evidence(st, c, tree):
    reviews, cases, unscoped = [], set(), []
    if c["kind"] != "round" or not awaiting_first_verdict(st):
        return reviews, cases, unscoped
    # Each next round records the tip at which the prior cycle stopped collecting evidence.
    for prior, following in zip(st["cycles"], st["rounds"][:c["n"]]):
        head = following["from"]
        run_ = selected_run(prior)
        checked = run_ and run_.get("done", True) and (tip := tree_id(tree, head)) and tip == tree_id(tree, run_["head"])
        if checked:
            if review_is_current(prior, baseline_review_target(st, prior, head)):
                reviews.clear()
            cases -= captured_cases(cases, latest_results(prior), tree, head)
        requests = outstanding_evidence(st, prior, tree, head)
        if (not checked or not review_is_current(prior, review_target(st, prior, tree, head, historical=True))
                or any(v["owed"] == "reviewer" for v, _ in requests)):
            reviews.append(cycle_label(prior))
        cases.update(pending_results(st, prior, tree, head))
        for v, missing in requests:
            if v["owed"] == "verify":
                if missing:
                    cases.update(missing)
                else:
                    unscoped.append((v, missing))
    return reviews, cases, unscoped


def cmd_verdict(plan, a):
    if a.engine is not None and not single_line(a.engine):
        raise Refuse("bad-engine", "--engine must be a nonblank single-line identifier", "supply the engine the judge runs on")
    with writing(plan) as st:
        require_consent(plan, st)
        c, md = cycle_of(st), plan_paths(plan)[0]
        settled(plan, st)
        owed = a.kind == "evidence-owed"
        if not owed:
            tree = require_current_checks(plan, st, c)
            require_evidence(st, c, tree, a.evidence_note)
        first = awaiting_first_verdict(st)
        if owed and (a.decide or not a.owed):
            raise Refuse("bad-owed", "an evidence-owed verdict names --owed reviewer|verify and takes no decisions", "record who owes what; decide when the evidence is in")
        if a.case and not (owed and a.owed == "verify"):
            raise Refuse("bad-owed-case", "--case applies only to evidence owed by Verify", "use `verdict evidence-owed --owed verify --case N`")
        if first and not owed and not (a.predicted and a.engine):
            raise Refuse("no-prediction", "the first verdict records the Prediction and the engine", "pass --predicted pass|round, --predict TEXT CAUSE (repeat) and --engine IDENTIFIER (nonblank, single-line)")
        if a.kind == "round" and not a.note:
            raise Refuse("no-notes", "a round verdict needs the judge's notes", "pass --note TEXT CAUSE for each")
        if a.kind != "round" and a.note:
            raise Refuse("notes-on-pass", f"a {a.kind} verdict takes no round notes", "use `verdict round`, or drop --note")
        if a.kind == "question" and not a.question:
            raise Refuse("no-question", "a question verdict needs the question", "pass --question TEXT")
        for _, cause in a.note or []:
            if cause not in CAUSES or cause == "task":
                raise Refuse("bad-cause", f"{cause!r} is not a cause for a judge's note", "use one of: " + ", ".join(CAUSES[:-1]))
        decided = {d[0] for d in a.decide or []}
        need = [i["id"] for i in items(c) if fate(c, i["id"]).startswith("open")] + [f["id"] for f in c["findings"] if f["kind"] == "convention"]
        known = need + [i["id"] for i in items(c)]
        bad = [d for d in decided if d not in known]
        if bad or any(d[1] not in ACTIONS for d in a.decide or []):
            raise Refuse("bad-decision", f"{', '.join(bad) or 'an action'} is not decidable here", "decide an Open entry or a Convention of the newest cycle as let-through, round or question")
        miss = [i for i in need if i not in decided] if not owed else []
        if miss:
            raise Refuse("undecided", f"{', '.join(miss)} has no decision", "pass --decide ID ACTION REASON for each Open entry and Convention")
        stop = (stop_reason(st) or converging_stop(st, len(a.note or []))) if a.kind == "round" else None
        v = {"n": len(st.get("verdicts", [])) + 1, "at": now(), "head": head_sha(md, tree_of(plan, st)), "cycle": cycle_label(c), "kind": a.kind,
             "epoch": epoch(st), "report": a.report, "evidence_note": a.evidence_note, "owed": a.owed if owed else None, "decisions": [{"id": i, "action": x, "reason": r} for i, x, r in a.decide or []],
             "notes": [], "stopped_notes": [], "question": a.question, "round": None, "stop": stop}
        if owed and a.owed == "reviewer":
            v["review_count"] = len(c.get("reviews", []))
        elif owed:
            for case in a.case:
                done_text(st, case)
            cases = set(a.case) or requested_result_cases(st, c, tree_of(plan, st), a.report)
            v.update(owed_cases=sorted(cases), result_count=len(c["results"]))
        ns = st.setdefault("notes", [])
        for text, cause in a.note or []:
            if stop:
                v["stopped_notes"].append([text, cause])
                continue
            ns.append({"n": 1 + max([x["n"] for x in ns], default=0), "text": text, "cause": cause, "by": "judge", "source": "judge", "round": None, "verdict": v["n"]})
            v["notes"].append(ns[-1]["n"])
        v["evidence"], v["contract"] = judge_evidence(st), contract_digest(plan, st)
        st.setdefault("verdicts", []).append(v)
        path = os.path.join(os.path.dirname(md), plan_slug(st) + ".judge.md")
        if first and not owed and not check_judge_file(path, optional=True):
            text = render_judge(st, v, a)
            open(path, "w", encoding="utf-8").write(text)
        write_notes(plan, st)
        print(f"verdict {v['n']}: {a.kind} at {v['head'][:7]}" + (f"; round stopped: {stop}; no round opens, the judge lands as on a pass" if stop else ""))
    return 0


def show_judging(st):
    out = []
    for v in st.get("verdicts", []):
        out.append(f"Verdict {v['n']}: {v['kind']} at {v['head'][:7]} ({v['cycle']})")
        out.append(f"  Report: {v['report']}")
        out += [f"  {d['id']} {d['action']} — {d['reason']}" for d in v["decisions"]]
        if v.get("evidence_note"):
            out.append(f"  evidence exception: {v['evidence_note']}")
        if v["kind"] == "evidence-owed":
            out.append(f"  owed by {v['owed']}: {v['report']}")
        out += [f"  note {n}" for n in v["notes"]] + ([f"  question: {v['question']}"] if v["question"] else [])
        if v.get("answer"):
            out.append(f"  answer: {v['answer']}")
        if v.get("stop"):
            out += [f"  Stopped: {v['stop']}"] + [f"  not taken: {t} — {c}" for t, c in v["stopped_notes"]]
    for r in st.get("rounds", []):
        out.append(f"Round {r['n']} ({author_role(r)}): " + (f"conflict at finish: {r['conflict']}" if r.get("conflict") else f"takes notes {', '.join(map(str, r['notes']))}") + (f"; done at {r['done']['head'][:7]}" if r["done"] else "; running"))
        if r["report"]:
            out.append(f"  report: {r['report']['became']} (" + ("commits: " + ", ".join(x[:7] for x in r["report"]["commits"]) if r["report"]["commits"] else "no commit") + ")")
    for title, ns in (("Open notes", open_notes(st)), ("Tasks", [n for n in st.get("notes", []) if n["cause"] == "task"])):
        if ns:
            out.append(f"{title}:")
            out += [f"  {n['n']}. {n['text']} — {n['cause']}" for n in ns]
    return out


def brief_judge(plan, st, cli, md, note):
    c = cycle_of(st)
    tree = require_current_checks(plan, st, c)
    owed = require_evidence(st, c, tree, note)
    ref = os.path.join(os.path.dirname(os.path.realpath(__file__)), "references", "judge.md")
    read_required(ref, "no-judge-md", "restore the judge rules or reinstall the plugin")
    slug, root = plan_slug(st), os.path.dirname(md)
    jf = os.path.join(root, slug + ".judge.md")
    asked = (st.get("verdicts") or [{}])[-1]
    asked = asked if asked.get("kind") == "question" else None
    answer = (asked or {}).get("answer") or note
    if asked and not answer:
        raise Refuse("no-answer", "the last verdict asked the human a question", "pass --note with the human's answer, in their words")
    first = awaiting_first_verdict(st)
    if not first and (asked or c["kind"] == "round"):
        check_judge_file(jf)
    out = [f"Judge rules: {ref}", f"Plan: {slug} — {st['title']}"]
    out += [f"Owed: {v['owed']} — {v['report']}" for v, _ in owed]
    if st.get("epic"):
        out.append("Epic: " + os.path.join(plan_checkout(md), st["epic"]["path"]))
    if first and c["kind"] == "round":
        out += ["First substantive verdict: read the full plan, gate and round evidence, and record the Prediction and engine.",
                "Decide only the current round's Open entries and Conventions."]
        baseline, cases, _ = baseline_evidence(st, c, tree)
        if baseline:
            out.append(f"The current baseline review recovers missing earlier evidence from {', '.join(baseline)}.")
        if captured := captured_cases(cases, latest_results(c), tree, "HEAD"):
            out.append("Current baseline captures recover earlier verification for Done " + ", ".join(map(str, sorted(captured))) + ".")
    for evidence in st["cycles"] if first else [c]:
        r = st["rounds"][evidence["n"] - 1] if evidence["kind"] == "round" else None
        if first and c["kind"] == "round":
            label = f"Round {r['n']}" if r else "Original gate"
            out += ["", f"## {label} evidence" + (" (current)" if evidence is c else ""), ""]
        if r:
            out += [f"Case: after round {r['n']} ({author_role(r)})"]
            if r.get("conflict"):
                out.append(f"Conflict at finish: {r['conflict']}")
            if not first:
                out.append(f"Judge file: {jf}")
            out += [*round_notes_file(md, st, r), "", f"### Round {r['n']}'s notes", ""]
            out += [note_line(st, n) for n in st["notes"] if n["round"] == r["n"]] + [""]
        else:
            out += ["Case: " + ("after the human's answer" if asked else "at the gate")]
            if asked:
                out.append(f"Judge file: {jf}")
            out += [f"Level: {evidence['level']}" + (f" (raised by {', '.join(evidence['raised_by'])})" if evidence["raised_by"] else ""), ""]
        if asked and evidence is c:
            out += [f"Question asked: {asked['question']}", f"The human's answer: {answer}", ""]
        if run_ := selected_run(evidence):
            out += show_run(run_, True)
        out += show_cycle(evidence, st)
        if r:
            out += ["Re-check verify: " + (e2e_text(st, r["n"]) or "no case to drive")]
        else:
            out += ["Open:"] + [f"  {i['id']} " + (f"{i['where']} — " if i.get("where") else "") + i["text"]
                               for i in items(evidence) if fate(evidence, i["id"]).startswith("open")]
            out += [f"Conventions: {', '.join(f['id'] for f in evidence['findings'] if f['kind'] == 'convention') or 'none'}",
                    "You check: " + (", ".join(str(d["n"]) for d in st.get("done", []) if human_case(evidence, d)) or "none")]
    return out + [""], f"{slug}.brief-judge-{cycle_label(c)}.md"


def brief_round(plan, st, cli, md, tree):
    shell_md = shlex.quote(md)
    rs = st.get("rounds", [])
    if not rs or rs[-1]["done"]:
        raise Refuse("no-round", "no round is running", "`pipeline.py round start` first")
    r = rs[-1]
    sk = sorted({x for p in st["phases"] for x in p["skills"] if x != "none"})
    out = [f"## Round {r['n']} takes", ""] + ([f"Conflict at finish: {r['conflict']}", ""] if r.get("conflict") else [])
    out += round_notes_file(md, st, r)
    out += [f"- {n['n']}. {n['text']} — {n['cause']}" for n in st["notes"] if n["round"] == r["n"]]
    out += ["", "Skills to read first: " + (", ".join(phase_instruction(tree, x) for x in sk) or "none"), ""] + spec_entry_lines(md) + ["## Record", "",
            f"- Your report: {cli} round report {shell_md} --became … --skills … --interfaces … --checks … [--commit <sha>] (repeat --commit; none when the round changed nothing)",
            f"- A ruling or product call: {cli} decision {shell_md} --by implementer --question … --from … --answer … --why … --cost …", ""]
    return out, f"{plan_slug(st)}.brief-round-{r['n']}.md"


# -- land: the shape file, the rewrite, the tree check, the record

LAND_STOPS = 2
NOT_MINE = (f":(exclude){WORKFLOW_DIR}",)


def shape_path(plan):
    return plan_paths(plan)[0][:-3] + ".shape.toml"


def land_stops(st):
    """The stops since the last land."""
    return [s for s in st.get("land_stops", []) if s["lands"] == len(st.get("lands", []))]


def land_git(tree, *args):
    r = git(*args, check=False, cwd=tree)
    if r.returncode:
        raise Refuse("git-failed", r.stderr.strip() or r.stdout.strip() or f"git {args[0]} failed", "fix the Git error and run it again")
    return r


def changed_paths(st, tree):
    r = land_git(tree, "diff", "--name-only", "-z", "--no-renames", f"{st['base']}..HEAD")
    return sorted(p for p in r.stdout.split("\0") if p)


def tstr(s):
    if "\n" not in s:
        return json.dumps(s, ensure_ascii=False)
    return '"""\n' + s.replace("\\", "\\\\").replace('"""', '\\"\\"\\"') + '"""'


def read_shape(plan):
    path = shape_path(plan)
    text = read_required(path, "no-shape", f"restore the commit shape or write it with `pipeline.py land draft {plan}`", newline="")
    try:
        v = tomllib.loads(text)
    except tomllib.TOMLDecodeError as e:
        raise Refuse("bad-shape", f"{path} is not valid TOML ({e})", "fix the TOML syntax in the shape")
    cs = v.get("commit")
    text = lambda c, k: type_ok(c.get(k), "str") and c[k].strip()
    if not (isinstance(cs, list) and cs and all(
            isinstance(c, dict) and type_ok(c.get("paths"), "list") and c["paths"] and all(map(norm, c["paths"]))
            and text(c, "message") and text(c, "walkthrough") for c in cs)):
        raise Refuse("bad-shape", f"{path}: every [[commit]] needs a list of paths, a message and a walkthrough, none empty", "fill them in")
    if "since" in v and not isinstance(v["since"], str):
        raise Refuse("bad-shape", f"{path}: since must be a string", "write what changed since the last land as text")
    return v


def cmd_land_draft(plan):
    md = plan_paths(plan)[0]
    head, tail = read_plan(md)
    st = load_state(plan, required=True)
    checked_plan(md, head, plan_root(md), check_references=False)
    if problems := drift_diags(plan, st, head, tail):
        raise refuse_all(problems)
    tree = tree_of(plan, st)
    on_branch(st, tree)
    changed = changed_paths(st, tree)
    last = (st.get("lands") or [None])[-1]
    cs, apart = [{"paths": changed, "message": "", "walkthrough": ""}], []
    if last:
        cs = [{**c, "paths": [p for p in map(norm, c["paths"]) if p in changed]} for c in last["shape"]]
        cs = [c for c in cs if c["paths"]]
        apart = [p for p in changed if not any(p in c["paths"] for c in cs)]
    out = ["# Edit each message and walkthrough, then run `pipeline.py land`."]
    if last:
        out += ['since = ""  # what changed since the last land']
        if apart:
            out += ["unplaced = " + json.dumps(apart, ensure_ascii=False) + "  # new paths: put each in a commit"]
    for c in cs:
        out += ["", "[[commit]]", "paths = " + json.dumps(c["paths"], ensure_ascii=False), "message = " + tstr(c["message"]), "walkthrough = " + tstr(c["walkthrough"])]
    path = shape_path(plan)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    print(f"land draft: {path}" + (f"; to place: {', '.join(apart)}" if apart else ""))
    return 0


def land_stop(st, tree, kind, message):
    """Record a stop; past the cap it is also a question to the human, held as a question verdict is."""
    stops = st.setdefault("land_stops", [])
    stops.append({"at": now(), "kind": kind, "message": message, "lands": len(st.get("lands", []))})
    n = len(land_stops(st))
    if n <= LAND_STOPS:
        return message
    vs = st.setdefault("verdicts", [])
    c = cycle_of(st)
    vs.append({"n": len(vs) + 1, "at": now(), "head": head_sha(None, tree), "cycle": cycle_label(c), "kind": "question", "owed": None,
               "epoch": epoch(st), "report": f"land stopped {n} times", "decisions": [], "notes": [], "stopped_notes": [],
               "question": message, "round": None, "stop": None})
    return f"{message}\nland has stopped {n} times: this is now a question for the human; ask it, then run the judge with `brief judge --note <their answer>`"


def next_backup(branch, tree):
    mine = re.compile(re.escape(f"backup/{branch}-") + r"(\d+)")
    names = land_git(tree, "branch", "--list", f"backup/{branch}-*", "--format=%(refname:short)").stdout.split()
    return f"backup/{branch}-{1 + max([int(m[1]) for b in names if (m := mine.fullmatch(b))], default=0)}"


def dirty_lines(tree):
    return land_git(tree, "status", "--porcelain", "--untracked-files=all", "--", ".", *NOT_MINE).stdout.splitlines()


def checked_land_shape(plan, st, tree):
    shape, changed = read_shape(plan), changed_paths(st, tree)
    seen, again = set(), set()
    for c in shape["commit"]:
        for p in map(norm, c["paths"]):
            (again if p in seen else seen).add(p)
    probs = [(code, f"{what} {', '.join(sorted(ps))}", fix) for code, what, ps, fix in (
        ("shape-missing", "the shape leaves out", set(changed) - seen, "place each path in a commit"),
        ("shape-repeats", "the shape puts in two commits", again, "put each path in one commit"),
        ("shape-unknown", f"the shape names paths {st['base'][:7]}..HEAD does not change:", seen - set(changed), "drop them")) if ps]
    if st.get("lands") and not str(shape.get("since", "")).strip():
        probs.append(("no-since", "a re-land needs `since` in the shape: what changed since the last land", "write it in the shape file"))
    if probs:
        raise refuse_all([(code, f"{shape_path(plan)}: {message}", fix) for code, message, fix in probs])
    return shape


def do_land(plan, st, tree):
    """-> a refusal to raise once the state is saved, or None."""
    g = lambda *a: land_git(tree, *a)
    lands = st.setdefault("lands", [])
    v = require_judge(plan, st)
    if lands and lands[-1]["difference"] and not lands[-1]["accepted"]:
        raise Refuse("undecided", f"land {lands[-1]['n']} left a difference from the checked tree", "keep it with `land accept --note`, or `land revert`")
    if dirty := dirty_lines(tree):
        msg = land_stop(st, tree, "dirty", "land stopped: the tree has uncommitted paths: " + ", ".join(l[3:] for l in dirty))
        return Refuse("dirty-tree", msg, "commit them to the branch or move them away, then land again")
    shape = checked_land_shape(plan, st, tree)
    prev = lands[-1] if lands else None
    pre, backup = g("rev-parse", "HEAD").stdout.strip(), next_backup(st["branch"], tree)
    stash = g("stash", "list").stdout.splitlines()
    g("branch", backup, pre)
    try:
        g("reset", "-q", st["base"])
        done = []
        for c in shape["commit"]:
            g("add", "-A", "-f", "--", *map(norm, c["paths"]))
            g("commit", "-q", "-m", c["message"])
            done.append({"paths": [norm(x) for x in c["paths"]], "message": c["message"], "walkthrough": c["walkthrough"], "sha": g("rev-parse", "HEAD").stdout.strip()})
        tip = done[-1]["sha"]
        held = set(map(norm, (p for c in shape["commit"] for p in c["paths"])))
        dirty = dirty_lines(tree)
        diff = {p for p in g("diff", "--name-only", "-z", backup, "HEAD").stdout.split("\0") if p and (p in held or not inside(p, [WORKFLOW_DIR]))} | {l[3:] for l in dirty}
        stat = g("diff", "--stat", backup, "HEAD").stdout.rstrip() if diff else None
        new_stash = g("stash", "list").stdout.splitlines()
        left = new_stash[:len(new_stash) - len(stash)]
        rd = g("range-diff", st["base"], prev["tip"], tip).stdout.rstrip() if prev else None
    except Refuse as error:
        try:
            g("reset", "-q", "--hard", pre)
        except Refuse as rollback:
            error.diags.append(("rollback-failed", str(rollback), f"the backup is {backup} at {pre}; fix the Git error, then restore it with `git reset --hard {backup}` in {tree}"))
        else:
            error.diags.append(("land-restored", f"the branch is restored to {pre}; backup {backup} is kept", "fix the Git error and land again"))
        raise
    lands.append({"n": len(lands) + 1, "at": now(), "backup": backup, "pre": pre, "tip": tip, "shape": done,
                  "judge": v["n"], "since": str(shape.get("since", "")).strip() or None, "range_diff": rd, "difference": sorted(diff), "stash": left, "accepted": None})
    print(f"land {len(lands)}: tip {tip[:7]} on {st['branch']}, {len(done)} commit(s), backup {backup} at {pre[:7]}")
    if not diff:
        print("the tip's tree is the backup's")
    else:
        print("the tip's tree differs from the backup's, which the checks passed:")
        print(stat)
        for l in dirty:
            print(f"  uncommitted: {l[3:]}")
        print("keep it with `land accept --note <why>`, or `land revert`")
    for s in left:
        print(f"a hook left a stash: {s}")
    return None


def cmd_land(plan, action, note):
    if action == "draft":
        return cmd_land_draft(plan)
    refusal = None
    with writing(plan, lambda st, tail: put_commits(st, tail, action == "revert")) as st:
        tree, lands = tree_of(plan, st), st.setdefault("lands", [])
        on_branch(st, tree)
        if action == "now":
            refusal = do_land(plan, st, tree)
        elif not lands or (action == "accept" and (not lands[-1]["difference"] or lands[-1]["accepted"])):
            raise Refuse("nothing-to-" + action, "no land left a difference to decide" if action == "accept" else "no land to revert", "land first")
        elif action == "accept":
            if not note:
                raise Refuse("no-note", "accepting a difference needs the reason", "pass --note: why the hook's change stays")
            if dirty_lines(tree):
                raise Refuse("dirty-tree", "the hook left uncommitted changes", "commit them, or `land revert`")
            lands[-1]["tip"] = land_git(tree, "rev-parse", "HEAD").stdout.strip()
            lands[-1]["accepted"] = {"at": now(), "note": note}
            print(f"land {lands[-1]['n']}: the difference is kept; the page says the tip is not the tree the checks passed")
        else:
            last = lands[-1]
            if mine := [l for l in dirty_lines(tree) if l[3:] not in last["difference"]]:
                raise Refuse("dirty-tree", "the tree has uncommitted paths: " + ", ".join(l[3:] for l in mine), "commit them to the branch or move them away, then revert; a reset would destroy them")
            land_git(tree, "reset", "-q", "--hard", last["backup"])
            lands.pop()
            if not lands:
                st.pop("page", None)
            why = f"land reverted to {last['backup']}" + (f": the hooks changed {', '.join(last['difference'])}" if last["difference"] else "") + (f" ({note})" if note else "")
            print(land_stop(st, tree, "revert", why))
    if refusal:
        raise refusal
    return 0


def put_commits(st, tail, cut=False):
    """The hand-written `## Human gate` with `### The commits` from the last land; with no land record the section stays as written unless cut (a revert of the last land)."""
    new = commits_section(st)
    if new is None and not cut:
        return tail
    mask = fenced(tail)
    i = next((k for k, l in enumerate(tail) if l.startswith("### The commits") and not mask[k]), None)
    if i is not None:
        j = next((k for k in range(i + 1, len(tail)) if tail[k].startswith(("## ", "### ")) and not mask[k]), len(tail))
        return tail[:i] + (new or []) + tail[j:]
    if not new:
        return tail
    while tail and not tail[-1].strip():
        tail = tail[:-1]
    return (tail or ["## Human gate"]) + [""] + new


def commits_section(st):
    """The `### The commits` lines (ending in a blank line) from the last land's record, or None."""
    lands = st.get("lands") or []
    if not lands:
        return None
    L, prev = lands[-1], lands[-2] if len(lands) > 1 else None
    out = [f"### The commits · landed {L['tip'][:7]} · {L['backup']}", ""]
    if L["accepted"]:
        out.append(f"The tip is not the tree the checks passed: a commit hook changed {', '.join(L['difference'])}; kept: {L['accepted']['note']}")
    elif L["difference"]:
        out.append(f"The tip is not the tree the checks passed: a commit hook changed {', '.join(L['difference'])}; undecided.")
    else:
        out.append(f"The tip has the tree the checks passed (the head `{L['pre'][:7]}` before the land). The commits before it were not checked.")
    out.append("")
    if prev:
        out += ["Since the last land:", "", L.get("since") or "", "", "```text", L.get("range_diff") or "", "```", ""]
    for c in L["shape"]:
        subject, _, body = c["message"].strip().partition("\n")
        out += [f"#### {subject} · `{c['sha'][:7]}`", ""] + ([body.strip(), ""] if body.strip() else []) + [f"Paths: " + ", ".join(f"`{p}`" for p in c["paths"]), "", c["walkthrough"].strip(), ""]
    sha = lambda cs: ", ".join(f"`{x[:7]}`" for x in cs)
    entry = lambda c, i: " ".join(x for x in (f"- {cycle_label(c)}", i["id"], i.get("where"), i["text"]) if x)
    fixes, rounds = [], []
    for c in st.get("cycles", []):
        for f in c["fixes"]:
            if f["report"]:
                fixes.append(f"- Fix {f['n']} ({cycle_label(c)}): {f['report']['became']} (commits {sha(f['report']['commits']) or 'none'})")
                fixes += ["  " + entry(c, i) for i in items_of(c, f["items"]) if i["id"] not in f["survived"]]
    for r in st.get("rounds", []):
        if r["report"]:
            rounds.append(f"- Round {r['n']} ({author_role(r)}): {r['report']['became']} (" + (f"commits {sha(r['report']['commits'])}" if r["report"]["commits"] else "no commit") + ")")
            rounds += [f"  - note {n['n']}. {n['text']}" for n in st["notes"] if n["round"] == r["n"]]
            for v in (v for v in st.get("verdicts", []) if v.get("round") == r["n"]):
                c = next((c for c in st["cycles"] if cycle_label(c) == v["cycle"]), None)
                for d in v["decisions"]:
                    if c and d["action"] == "round" and (x := entry_of(c, d["id"])):
                        rounds.append(f"  {entry(c, x)} (decided: round — {d['reason']})")
    if fixes or rounds:
        out += ["The gate's fixes and rounds; the backup keeps their commits:", ""] + fixes + rounds + [""]
    return out


ENDINGS = {"merge-request": "a merge request into `{}`", "ff-only": "a fast-forward into `{}`", "no-ff": "a merge commit into `{}`"}


def tree_id(tree, rev):
    r = git("rev-parse", f"{rev}^{{tree}}", check=False, cwd=tree)
    return None if r.returncode else r.stdout.strip()


def flagger(plan, st):
    """-> flag(commit): a note for a record taken on a tree other than the last land's tip or its pre-land head, else ''."""
    L, tree = st["lands"][-1], tree_fact(plan, st)
    tree = tree if os.path.isdir(tree) else plan_root(plan_paths(plan)[0])
    good = {tree_id(tree, L["tip"]), tree_id(tree, L["pre"])} - {None}

    def flag(commit):
        if not commit:
            return " [unknown commit: not known to be the tip's tree]"
        if tree_id(tree, commit) in good:
            return ""
        paths = git("diff", "--name-only", "-z", commit, L["tip"], "--", ".", *NOT_MINE, check=False, cwd=tree).stdout.split("\0")
        return f" [taken on `{commit[:7]}`, not the tip's tree]" + (f" (changed since: {', '.join(p for p in paths if p)})" if any(paths) else "")
    return flag


def last_results(st):
    last = {}
    for c in st.get("cycles", []):
        last.update(latest_results(c))
    return last


def gate_decided(st):
    out = ["### Decided without you", ""]
    for d in st.get("decisions", []):
        out.append(f"- {d['question']} → {d['answer']}. why: {d['why']}; cost if wrong: {d['cost']} (by {d['by']}, from {d['source']}" + (f", phase {d['phase']}" if d["phase"] else "") + ")")
    for h in st["history"]:
        if h.get("note") and h["what"] not in ("approved", "adopted", "validated", "plan approval", "run approval", "summary approval") and not (h["what"] == "status" and h["to"] == "passed"):
            out.append(f"- {h['what']}: {h['from'] if h['from'] is not None else '-'} → {h['to']} @{(h['sha'] or '-')[:7]}: {h['note']}")
    return out + ([] if len(out) > 2 else ["Nothing."]) + [""]


def gate_open(st, flag):
    """What is still open: the last verdict, and every entry no fix or round closed; a closed entry shows under its fix or round."""
    out = ["### Open", ""]
    if v := (st.get("verdicts") or [None])[-1]:
        out.append(f"- Verdict {v['n']}: {v['kind']} at `{v['head'][:7]}` ({v['cycle']}){flag(v['head'])} — {v['report']}")
        out += [f"  - owed by {v['owed']}"] if v["owed"] else []
        out += [f"  - evidence exception: {v['evidence_note']}"] if v.get("evidence_note") else []
        out += [f"  - question: {v['question']}" + (f" Answer: {v['answer']}" if v.get("answer") else "")] if v["question"] else []
        out += [f"  - round notes: {', '.join(map(str, v['notes']))}"] if v["notes"] and v.get("round") is None else []
        out += [f"  - stopped: {v['stop']}"] if v.get("stop") else []
        out += [f"  - stopped proposal: {text} — {cause}" for text, cause in v.get("stopped_notes", [])]
    dec, left = decisions(st), []
    for c in st.get("cycles", []):
        label = cycle_label(c)
        note = lambda i: (f" (decided: {dec[(label, i)][1]['action']} — {dec[(label, i)][1]['reason']})" if (label, i) in dec else "")
        left += [f"- {label} {i['id']} {i.get('where', '')} {i['text']} ({fate(c, i['id'])}){note(i['id'])}".replace("  ", " ")
                 for i in items(c) if fate(c, i["id"]).startswith("open") and not closed_by(st, c, i["id"])]
        left += [f"- {label} {f['id']} {f['kind']} {f['where'] or ''} {f['text']}{note(f['id'])}".replace("  ", " ")
                 for f in c["findings"] if f["kind"] != "defect" and not closed_by(st, c, f["id"])]
    left += [f"- Done {n} not reached: {r['detail']}" for n, r in sorted(last_results(st).items()) if r["outcome"] == "not reached"]
    return out + left + ([] if len(out) > 2 or left else ["Nothing."]) + [""]


def gate_e2e(plan, st, flag):
    out = ["### E2E", ""]
    gate = next((c for c in st.get("cycles", []) if c["kind"] == "gate"), None)
    if gate:
        out += [f"Level: {gate['level']}" + (f", raised by {', '.join(gate['raised_by'])}" if gate["raised_by"] else ""), ""]
    for c in st.get("cycles", []):
        if r := selected_run(c):
            out.append(f"- Checks ({cycle_label(c)}) at `{r['head'][:7]}`: {'red' if any(x['red'] for x in r['commands']) else 'green'}{flag(r['head'])}")
    last = last_results(st)
    for mine in (False, True):
        for d in st.get("done", []):
            if bool(human_case(gate, d) if gate else d["you_check"]) != mine:
                continue
            r = last.get(d["n"])
            if r is None:
                out.append(f"- {d['n']}. {d['text']} — " + ("you check" if mine else "no result"))
                continue
            capture = r["capture"]
            out.append(f"- {d['n']}. {r['do']} → {r['see']} — {r['outcome']}" + (f": {r['detail']}" if r["detail"] else "") + f" — {capture or '-'} — at `{(r.get('commit') or '-')[:7]}`{flag(r.get('commit'))}"
                       + (" — you check" if mine else ""))
    return out + [""]


def render_gate(plan, st):
    """The whole `## Human gate` from the records: the page once `page` ran, then the last land's commits."""
    out, pg = ["## Human gate", ""], st.get("page")
    if pg and st.get("lands"):
        flag, how, target = flagger(plan, st), pg["ending"]["how"], pg["ending"]["target"]
        out += ["### How to try it", "", pg["note"], "", "### Ending", "", f"The run ends in {ENDINGS[how].format(target)}; your word at the gate approves it.", ""]
        if pg["message"]:
            out += ["Request title:" if how == "merge-request" else "Merge message:", "", "```text", pg["message"], "```", ""]
        out += gate_decided(st) + gate_open(st, flag) + gate_e2e(plan, st, flag)
    return out + (commits_section(st) or [])


def read_guide(plan, st, a):
    source = os.path.abspath(a.guide_file) if a.guide_file is not None else f"--guide for {plan_paths(plan)[0]}"
    example = os.path.join(os.path.dirname(os.path.abspath(__file__)), "references", "example.guide.md")
    fix = f"follow the example at {example} and run `page` again"
    guide = read_required(source, "bad-guide", fix, newline="") if a.guide_file is not None else a.guide

    def bad(problem):
        return Refuse("bad-guide", f"{source}: {problem}", fix)

    try:
        guide.encode("utf-8")
    except UnicodeEncodeError:
        raise bad("the guide is not valid UTF-8") from None
    lines = markdown_newlines(guide).split("\n")
    headings = [i for i, (line, hidden) in enumerate(zip(lines, fenced(lines)))
                if not hidden and re.match(r"^#{1,4}(?:\s|$)", line)]
    if (len(headings) != 2 or any(not re.fullmatch(r"####\s+\S.*", lines[i]) for i in headings)
            or not any(line.strip() for line in lines[:headings[0]])):
        raise bad("give the location and setup, then exactly two level-four headings for the checks and decisions")

    start, end = headings
    checks = [line for line in lines[start + 1:end] if line.strip()]
    choices = [line for line in lines[end + 1:] if line.strip()]
    if not checks or not choices:
        raise bad("each list needs bullets or a lone `- —` for an empty list")
    if choices != ["- —"] and any(not line.startswith("- ") or line[2:].strip() in ("", "—") for line in choices):
        raise bad("give each outstanding decision its own bullet, or use a lone `- —`")

    gate = next((c for c in st["cycles"] if c["kind"] == "gate"), cycle_of(st))
    done = {f"Done {d['n']}": d for d in st.get("done", [])}
    seen = set()
    for line in [] if checks == ["- —"] else checks:
        match = re.fullmatch(r"- \*\*(Done [0-9]+|Check [1-9][0-9]*)\*\*\s+(.*?) → (.*)", line)
        if not match or not all(part.strip() for part in match.groups()[1:]):
            raise bad(f"write each check as `- **Done N** action → visible result` or `- **Check N** action → visible result`: {line!r}")
        ref = match[1]
        if ref in seen:
            raise bad(f"{ref} appears twice; use each check reference once")
        if ref.startswith("Done ") and ref not in done:
            raise bad(f"{ref} is not in the plan; use a current Done reference or `Check N` for an extra check")
        seen.add(ref)
    missing = [ref for ref, d in done.items() if human_case(gate, d) and ref not in seen]
    if missing:
        raise bad("add the manual checks for " + ", ".join(missing))
    return guide


def cmd_page(plan, a):
    if a.show:
        if a.message is not None:
            raise Refuse("bad-page", "`--show` reads the recorded guide", "omit --message")
        md = plan_paths(plan)[0]
        head, tail = read_plan(md)
        st = load_state(plan, required=True)
        if problems := drift_diags(plan, st, head, tail):
            raise refuse_all(problems)
        sys.stdout.buffer.write(require_page(plan, st)["note"].encode("utf-8"))
        return 0

    with writing(plan) as st:
        require_judge(plan, st)
        if not st.get("lands"):
            raise Refuse("no-land", "the branch is not landed", "the page follows a land: run `pipeline.py land`")
        last = st["lands"][-1]
        if head_sha(None, tree_of(plan, st)) != last["tip"] or git("rev-parse", f"refs/heads/{st['branch']}", check=False, cwd=tree_of(plan, st)).stdout.strip() != last["tip"] or (last["difference"] and not last["accepted"]) or dirty_lines(tree_of(plan, st)):
            raise Refuse("land-stale", "the current branch differs from its accepted land", "land the current result before rendering its page")
        if st["status"] not in ("building", "at the human gate"):
            raise Refuse("bad-status", f"the plan is {st['status']}", "the page is made while building or at the human gate")
        fin = (st.get("run") or {}).get("finish")
        if not fin:
            raise Refuse("no-run-values", "the plan has no approved run values", "write the run file and run `pipeline.py approve`")
        for _, m, f in run_drift(plan, st):
            print(f"Drift: {m} — fix: {f}", file=sys.stderr)
        if fin["how"] != "ff-only" and not a.message:
            raise Refuse("no-message", f"a run ending in {fin['how']} needs the merge message or request title", "pass --message")
        guide = read_guide(plan, st, a)
        st["page"] = {"at": now(), "note": guide, "message": a.message, "ending": {"how": fin["how"], "target": fin["target"]}, "binding": page_binding(plan, st)}
        set_plan(plan, st, status="at the human gate")
    sys.stdout.buffer.write(guide.encode("utf-8"))
    return 0


# -- finish: the run file's ending, in code

def remote_url(root):
    r = git("remote", "get-url", "origin", check=False, cwd=root)
    return r.stdout.strip() if not r.returncode else None


def forge_of(url):
    """The forge a remote URL (or a request's link) names: github, gitlab or None."""
    m = re.match(r"^(?:[a-z][a-z+.-]*://(?:[^@/]*@)?|[^@/:]+@)([^/:]+)", url or "", re.I)
    host = m[1].lower() if m else ""
    return "github" if "github" in host else "gitlab" if "gitlab" in host else None


def tool(args, cwd):
    try:
        return subprocess.run(args, capture_output=True, text=True, cwd=cwd)
    except OSError as e:
        return subprocess.CompletedProcess(args, 127, "", str(e))


def merge_conflict(st, fin, why):
    return Refuse("merge-refused", why, f"nothing changed; a conflict round rebases the branch: `pipeline.py round start --conflict \"<what>\"`, then the judge, `land` and `page` again, and `finish` on {fin['target']}'s new head")


def local_merge(st, root, fin):
    """Merge the plan's branch into the target in the clean tree that has it, else here after switching; -> the merge's head. Refused, the tree is as it was."""
    branch, target = st["branch"], fin["target"]
    if git("rev-parse", "--verify", "-q", f"refs/heads/{target}", check=False, cwd=root).returncode:
        raise Refuse("no-target", f"the run file's target {target} is not a branch here", "fix `[finish].target` and approve again")
    msg = (st.get("page") or {}).get("message")
    if fin["how"] == "no-ff" and not msg:
        raise Refuse("no-message", "a no-ff merge needs the merge message the page recorded", "run `pipeline.py page --guide-file PATH --message TEXT`")
    tree = branch_tree(root, target)
    was = None if tree else git("branch", "--show-current", cwd=root).stdout.strip() or ("--detach", git("rev-parse", "HEAD", cwd=root).stdout.strip())
    tree = tree or root
    if dirty := dirty_lines(tree):
        raise Refuse("dirty-target", f"{tree} has uncommitted paths: " + ", ".join(l[3:] for l in dirty), "commit them or move them away, then finish again")
    g = lambda *a: git(*a, check=False, cwd=tree)
    if g("rev-parse", "--verify", "-q", "MERGE_HEAD").returncode == 0:
        raise Refuse("merge-in-progress", f"{tree} already has a merge in progress", "finish or abort that merge before running finish")
    if was and (r := g("switch", "--no-overwrite-ignore", target)).returncode:
        raise Refuse("git-failed", r.stderr.strip(), "fix the tree and finish again")
    args = ["--no-ff", "-m", msg] if fin["how"] == "no-ff" else ["--ff-only"]
    r = g("merge", "--no-overwrite-ignore", *args, st["lands"][-1]["tip"])
    if r.returncode:
        paths = g("diff", "--name-only", "--diff-filter=U").stdout.split()
        if g("rev-parse", "--verify", "-q", "MERGE_HEAD").returncode == 0:
            g("merge", "--abort")
        if was:
            g("switch", *(was if isinstance(was, tuple) else (was,)))
        why = (f"merging {branch} into {target} conflicts in " + ", ".join(paths)) if paths else (r.stderr.strip() or r.stdout.strip()).splitlines()[-1]
        raise merge_conflict(st, fin, why)
    return g("rev-parse", "HEAD").stdout.strip()


def open_request(plan, st, root, fin):
    """Push the plan's branch and open its request by the forge the remote names; -> the link, or None when the agent opens it."""
    branch, target = st["branch"], fin["target"]
    msg = (st.get("page") or {}).get("message")
    if not msg:
        raise Refuse("no-message", "a merge request needs the title the page recorded", "run `pipeline.py page --guide-file PATH --message TEXT`")
    url = remote_url(root)
    if not url:
        raise Refuse("no-remote", "the repository has no remote `origin`", "add it, or end the run locally")
    forge, title = forge_of(url), msg.splitlines()[0]
    if forge is None:
        print(f"finish: {url} is no forge this knows: nothing was pushed")
        print(f"open the merge request from {branch} into {target} titled {title!r}, then record its link with `pipeline.py plan status {plan} <link>`; once it is merged, `pipeline.py finish --merged {plan}`")
        return None
    push = ["git", "push", "-u", "origin", branch] + (["-o", "merge_request.create", "-o", f"merge_request.target={target}", "-o", f"merge_request.title={title}"] if forge == "gitlab" else [])
    r = tool(push, root)
    if r.returncode:
        raise Refuse("push-failed", (r.stderr.strip() or r.stdout.strip()), "fix the remote and finish again")
    out = r.stdout + r.stderr
    if forge == "github":
        body = "\n".join(msg.splitlines()[1:] + render_gate(plan, st)[1:])
        r = tool(["gh", "pr", "create", "--base", target, "--head", branch, "--title", title, "--body", body], root)
        if r.returncode:
            return Refuse("gh-failed", f"{branch} was pushed; gh pr create: " + (r.stderr.strip() or r.stdout.strip()), "open the request yourself and record its link with `pipeline.py plan status`")
        out = r.stdout
    links = re.findall(r"https?://\S+", out)
    link = next((l for l in reversed(links) if forge == "github" or "/merge_requests/" in l), None)
    print(f"finish: pushed {branch} to origin")
    if link is None:
        print(f"finish: the forge printed no link: find the request and record its link with `pipeline.py plan status {plan} <link>`")
        return "pushed"
    return link


def request_merged(plan, st, link, merged):
    """Whether the request is merged: GitHub answers through `gh`; elsewhere the agent says so with --merged."""
    if merged:
        return True
    if forge_of(link) != "github":
        print(f"finish: {link} is not on GitHub: once it is merged, `pipeline.py finish --merged {plan}`")
        return False
    r = tool(["gh", "pr", "view", link, "--json", "state"], plan_root(plan_paths(plan)[0]))
    try:
        state = json.loads(r.stdout)["state"]
    except (ValueError, KeyError, TypeError):
        raise Refuse("gh-failed", "gh pr view gave no state: " + (r.stderr.strip() or r.stdout.strip()), "look at the request and run `pipeline.py finish --merged` if it is merged")
    if state != "MERGED":
        print(f"finish: {link} is {state.lower()}; nothing changes")
    return state == "MERGED"


def clean_up(plan, st, root, fin):
    """Remove only resources owned by the finished run. Return a reason if cleanup must wait."""
    from runweld_release import ReleaseError
    branch = st["branch"]
    task = task_for(plan, root)
    expected = task["tree"] if task else st.get("tree")
    wt = branch_tree(root, branch)
    if expected and os.path.realpath(expected) != os.path.realpath(root):
        if wt != expected and os.path.lexists(expected):
            return f"worktree {expected} is no longer registered to {branch}; it stays"
        if wt == expected:
            if os.path.isdir(wt):
                if task:
                    try:
                        clean_setup_outputs(task, wt)
                    except (OSError, ReleaseError) as error:
                        return f"worktree {wt} stays: {error}"
                r = git("status", "--porcelain", "--untracked-files=all", "--ignored", check=False, cwd=wt)
                if r.returncode or r.stdout.strip():
                    return f"worktree {wt} stays with unsaved or ignored paths: " + (r.stderr.strip() or ", ".join(l[3:] for l in r.stdout.splitlines()))
            r = git("worktree", "remove", wt, check=False, cwd=root)
            if r.returncode:
                return f"worktree {wt} stays: {r.stderr.strip()}"
            print(f"finish: worktree {wt} removed")
    d = (st.get("alloc") or {}).get("data_dir")
    if d and os.path.lexists(d):
        owned = Path(task["artifacts"]) / "data" if task else Path(plan_paths(plan)[0]).with_suffix(".data")
        if Path(d) != owned or owned.resolve() != owned or not owned.is_dir():
            return f"data directory {d} is no longer at its owned path; it stays"
        try:
            shutil.rmtree(d)
        except OSError as error:
            return f"data directory {d} stays: {error}"
        print(f"finish: data directory {d} removed")
    mine = re.compile(re.escape(f"backup/{branch}-") + r"\d+")
    names = [b for b in git("branch", "--list", f"backup/{branch}-*", "--format=%(refname:short)", check=False, cwd=root).stdout.split() if mine.fullmatch(b)]
    if names and fin["delete_backups"]:
        result = git("branch", "-D", *names, check=False, cwd=root)
        if result.returncode:
            return f"backups stay: {result.stderr.strip()}"
        print("finish: backups deleted: " + ", ".join(names))
    elif names:
        print("finish: backups kept (the run file keeps them): " + ", ".join(names))
    print(f"finish: branch {branch} stays")


def clean_setup_outputs(task, tree):
    _, outputs = setup_ownership(task)
    if not outputs:
        return
    ignored = setup_paths(tree, ignored=True)
    if ignored is None:
        raise OSError("cannot verify which setup paths are still ignored")
    for name in ignored.intersection(outputs):
        if outputs[name] == setup_identity(tree, name):
            (Path(tree) / name).unlink(missing_ok=True)


def cmd_finish(plan, merged):
    plan = plan_paths(plan)[0]
    root = plan_root(plan)
    with writing(plan) as st:
        fin, status = (st.get("run") or {}).get("finish"), st["status"]
        if not fin:
            raise Refuse("no-run-values", "the plan has no approved run values", "write the run file and run `pipeline.py approve`")
        if status == "merged" and st.get("cleanup_pending") and not merged:
            return finish_cleanup(plan, st, root, fin)
        for _, m, f in run_drift(plan, st):
            print(f"Drift: {m} — fix: {f}")
        if (pg := st.get("page")) and pg["ending"] != {"how": fin["how"], "target": fin["target"]}:
            raise Refuse("page-differs", f"the page the human approved names {pg['ending']['how']} into {pg['ending']['target']}; the run file's approved ending is {fin['how']} into {fin['target']}",
                         "set the plan back with `plan status \"at the human gate\"`, run `pipeline.py page` again so the page names the new ending, and take the human's word on it")
        link = status.startswith("http")
        if not link and status not in ("passed",):
            raise Refuse("bad-status", f"the plan is {status}, not passed or a merge request's link", "finish follows current authorized `accept` at the human gate")
        require_acceptance(plan, st)
        if link and (not st.get("request") or st["request"]["tip"] != git("rev-parse", st["branch"], cwd=root).stdout.strip() or st["request"]["acceptance"] != digest(st["acceptance"])):
            raise Refuse("no-request", "the request has no current authorized finish record", "finish the currently accepted result before recording its link")
        if merged and not link:
            raise Refuse("no-request", "--merged names a request, and the plan has none", "finish opens it first")
        if link:
            if not request_merged(plan, st, status, merged):
                return 0
            how = f"merge request {status}"
            integration = {"request": status}
        elif fin["how"] == "merge-request":
            tip = git("rev-parse", st["branch"], check=False, cwd=root).stdout.strip()
            if (st.get("pushed") or {}).get("tip") == tip:
                raise Refuse("pushed-no-link", f"{st['branch']} was pushed and the forge printed no link", f"find the request and record its link with `pipeline.py plan status {plan} <link>`; nothing is pushed again")
            got = open_request(plan, st, root, fin)
            st["request"] = {"at": now(), "tip": tip, "acceptance": digest(st["acceptance"])}
            if isinstance(got, Refuse):
                st["pushed"] = {"at": now(), "tip": tip}
                for code, message, fix in got.diags:
                    print(f"{code}: {message} — fix: {fix}")
                return 1
            if got == "pushed":
                st["pushed"] = {"at": now(), "tip": tip}
            elif got:
                set_plan(plan, st, status=got, note="merge request opened")
                print(f"finish: {got} is the plan's Status; {fin['target']} is untouched")
            return 0
        else:
            common = Path(git("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=root).stdout.strip())
            with (common / "runweld-integration.lock").open("a") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                require_acceptance(plan, st)
                commit = local_merge(st, root, fin)
                how = f"{fin['how']} into {fin['target']} at {commit[:7]}"
            integration = {"commit": commit}
        set_plan(plan, st, status="merged", note=how)
        st["integration"] = {"how": fin["how"], "target": fin["target"], "landed": st["lands"][-1]["tip"], **integration}
        st["cleanup_pending"] = "finish cleanup is pending"
        save(plan, st, *read_plan(plan_paths(plan)[0]))
        print(f"finish: {plan_slug(st)} merged ({how})" + ("" if link else "; nothing was pushed"))
        return finish_cleanup(plan, st, root, fin)


def finish_cleanup(plan, st, root, fin):
    with contextlib.ExitStack() as locks:
        reason = None
        if task := task_for(plan, root):
            artifacts = workflow_subdir(Path(task["artifacts"]))
            if artifacts.is_dir():
                lock = locks.enter_context((artifacts / ".setup.lock").open("a"))
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    reason = "task setup is still running"
        reason = reason or clean_up(plan, st, root, fin)
    if reason:
        st["cleanup_pending"] = reason
        print(f"finish: {reason}. Resolve it and run `finish` on the plan again; integration is already recorded.")
    else:
        st.pop("cleanup_pending", None)
    return 0


def finish_and_report(plan, merged, as_json):
    plan = plan_paths(plan)[0]
    root = plan_root(plan)
    os.chdir(root)
    with contextlib.redirect_stdout(io.StringIO()) if as_json else contextlib.nullcontext() as output:
        result = cmd_finish(plan, merged)
    facts = cmd_status(plan, False, root, as_data=True)
    integration = facts["integration"]
    if integration and integration.get("commit"):
        ref = f"refs/heads/{integration['target']}"
        integration["target_head"] = git("rev-parse", "--verify", "-q", ref, check=False, cwd=root).stdout.strip() or None
        integration["verified"] = git("merge-base", "--is-ancestor", integration["commit"], ref, check=False, cwd=root).returncode == 0
    actions = facts["workflow"]["actions"]
    if as_json:
        print(json.dumps({"status": facts["status"], "integration": integration, "cleanup_pending": facts["cleanup_pending"],
                          "actions": actions, "messages": output.getvalue().splitlines()}, ensure_ascii=False))
    else:
        if integration and "verified" in integration:
            result_text = "contains" if integration["verified"] else "does not contain"
            print(f"finish: {integration['target']} {result_text} integration commit {integration['commit']}")
        show_next(actions)
    return result or (1 if integration and integration.get("verified") is False else 0)


def show_land(st):
    lands = st.get("lands") or []
    out = []
    if lands:
        L = lands[-1]
        out.append(f"Land {L['n']}: tip {L['tip'][:7]} has the tree of {L['pre'][:7]}" + (
            " (not the checked tree; undecided)" if L["difference"] and not L["accepted"] else
            f" (not the checked tree; kept: {L['accepted']['note']})" if L["accepted"] else "")
            + f"; {L['backup']} holds the commits earlier records name")
    for s in land_stops(st):
        out.append(f"Land stop ({s['kind']}): {s['message']}")
    return out


class ParseExit(Exception):
    pass


class RoutingParser(argparse.ArgumentParser):
    def _print_message(self, message, file=None):
        pass

    def exit(self, status=0, message=None):
        raise ParseExit


def discovery_options(parser):
    parser.add_argument("--result", help="settled decisions or the evidenced cause")
    questions = parser.add_mutually_exclusive_group()
    questions.add_argument("--question", dest="questions", action="append", help="current open question (repeat for all)")
    questions.add_argument("--clear-questions", action="store_true", help="record that no open questions remain")
    parser.add_argument("--reason", help="why an optional stage was skipped")
    parser.add_argument("--command", dest="repro_command", help="repeatable command for the red reproduction")
    parser.add_argument("--artifact", help="saved evidence under the task's artifacts")
    parser.add_argument("--json", action="store_true")


def parse_cli(argv, *, standalone=False, routing=False, version=None):
    parser = RoutingParser if routing else argparse.ArgumentParser
    p = parser(prog="runweld" if standalone else "pipeline.py")
    if standalone:
        release = version or "runweld"
        cli_version = release.partition("@")[0]
        if not routing and argv in (["--version", "--verbose"], ["--verbose", "--version"]):
            print(f"CLI version: {cli_version}\nBuild ID: {release}")
            p.exit()
        p.add_argument("--version", action="version", version=cli_version,
                       help="show the CLI and any pinned project version; add --verbose for build IDs")
    top = p.add_subparsers(dest="group", required=True)
    if standalone:
        p.description = "Start in a Git checkout with `runweld next`. Use `runweld help agents` for the workflow."
        help_parser = top.add_parser("help", help="show terminal help or the installed agent workflow")
        help_parser.add_argument("topic", choices=("agents",), nargs="?")
        help_parser.add_argument("--plan", help="show help for this run's release")
        reference = top.add_parser("reference", help="print a text resource from the selected release")
        reference.add_argument("resource", help="the release-relative path from an instruction")
        reference.add_argument("--plan", help="use a task's pinned release")
        handoff = top.add_parser("handoff", help="print handoff instructions or validate a live Herdr destination")
        handoff_actions = handoff.add_subparsers(dest="command", required=True)
        herdr = handoff_actions.add_parser("herdr", help="check the live workspace and pane before dispatch")
        herdr.add_argument("plan", help="the assignment's plan path")
        herdr.add_argument("--workspace", required=True, help="live Herdr workspace ID")
        herdr.add_argument("--pane", required=True, help="live Herdr pane ID")
        herdr.add_argument("--agent", help="name of the live agent for an existing assignment")
        next_parser = top.add_parser("next", help="find available actions from this project or task")
        next_parser.add_argument("--json", action="store_true", help="print the same facts and actions as JSON")
        next_parser.add_argument("--provider", help="the current provider for executable brief commands")
        next_scope = next_parser.add_mutually_exclusive_group()
        next_scope.add_argument("id", nargs="?", help="task ID; omit inside its worktree")
        next_scope.add_argument("--plan", help="inspect a task by its plan path")
        init = top.add_parser("init", help="initialize project defaults and the current provider's executor pair")
        init.add_argument("--non-interactive", action="store_true", help="use supplied values and defaults without prompting")
        init.add_argument("--provider", help="provider identifier (otherwise detected when unambiguous)")
        for tier in ("primary", "secondary"):
            init.add_argument(f"--{tier}-model", help=f"{tier} model identifier")
            init.add_argument(f"--{tier}-effort", help=f"{tier} effort identifier (optional)")
        init.add_argument("--phase-check", action="append", help="phase check command (repeatable)")
        init.add_argument("--full-check", action="append", help="full check command (repeatable)")
        init.add_argument("--build", help="optional project build command")
        init.add_argument("--port", action=argparse.BooleanOptionalAction, help="allocate a port per task (default: false)")
        init.add_argument("--data-dir", action=argparse.BooleanOptionalAction, help="allocate a data directory per task (default: false)")
        init.add_argument("--dev", help="optional development server command")
        init.add_argument("--url", "--dev-url", help="optional development server URL")
        init.add_argument("--setup", "--bootstrap", help="optional existing command to prepare a task's worktree when needed")
        update_parser = top.add_parser("update", help="update the CLI or this project's release")
        scopes = update_parser.add_mutually_exclusive_group()
        scopes.add_argument("--cli", dest="scope", action="store_const", const="cli",
                            help="install the current upstream CLI in this launcher's prefix")
        scopes.add_argument("--project", dest="scope", action="store_const", const="project",
                            help="select an installed build for new tasks in this project")
        update_parser.add_argument("version", nargs="?", metavar="RELEASE", help="exact release ID (default: most recently installed)")
        paths = top.add_parser("path", help="print the shared local workflow path without creating it")
        paths.add_argument("area", nargs="?", help="optional category under the project workflow")
        task_commands = top.add_parser("task", help="start or resume a task in its own worktree").add_subparsers(dest="command", required=True)
        for name in ("start", "resume", "path", "setup", "stage"):
            task = task_commands.add_parser(name)
            if name == "setup":
                task.add_argument("plan", help="the task's plan path")
                task.add_argument("--reproduction", action="store_true", help="prepare an active bug investigation before planning")
                task.add_argument("--preview", action="store_true", help="show the setup command and effects without running it")
                continue
            if name == "stage":
                task.add_argument("plan", help="the task's plan path")
                task.add_argument("stage", choices=("grill", "prototype", "reproduce", "plan"))
                task.add_argument("event", choices=("start", "save", "done", "skip"))
                discovery_options(task)
                continue
            task.add_argument("id", help="stable task ID (lowercase letters, numbers and hyphens)")
            if name == "path":
                task.add_argument("area", nargs="?", help="optional category under the task's artifacts")
            else:
                task.add_argument("--json", action="store_true")
            if name == "start":
                task.add_argument("--base", help="project base ref (default: source checkout HEAD)")
                task.add_argument("--goal", help="the task's requested outcome")
                task.add_argument("--bug", action="store_true", help="require a red reproduction before planning")
                task.add_argument("--finish-how", choices=CHOICES["finish", "how"], help="agreed ending for this run")
                task.add_argument("--finish-target", help="integration branch for this run")
                task.add_argument("--delete-backups", action=argparse.BooleanOptionalAction, help="delete backups after this run finishes")
            if name == "resume":
                task.add_argument("--provider", help="the current provider for executable brief commands")
    sp = top.add_parser("spec", prog=f"{p.prog} spec")
    sub = sp.add_subparsers(dest="command", required=True)
    for name in ("check", "write"):
        s = sub.add_parser(name)
        s.add_argument("--base")
        s.add_argument("plan")
    sub.add_parser("list")
    sub.add_parser("show").add_argument("id")
    s = top.add_parser("approve", help="compile a plan into its state, with a strict check")
    s.add_argument("--json", action="store_true", help="print the result as JSON")
    s.add_argument("plan", help="the plan file")
    s = top.add_parser("status", help="one plan's state, the live inventory, or current workflow guidance")
    s.add_argument("--json", action="store_true", help="print as JSON")
    s.add_argument("--provider", help="the current provider for executable brief commands in workflow guidance")
    status_scope = s.add_mutually_exclusive_group()
    status_scope.add_argument("plan", nargs="?", help="the plan file, any status; omit to list all project plans" if standalone else
                              "the plan file, any status; omit to list plans from building through passed")
    status_scope.add_argument("--current", action="store_true", help="show the steps for relevant plans from the current checkout")
    s = top.add_parser("workflow", help="show the workflow before there is a plan")
    s.add_argument("--stage", help="show a stage's inputs, roles and transitions")
    s.add_argument("--json", action="store_true", help="print the workflow as JSON")
    pp = top.add_parser("plan", help="the plan's own status and base")
    psub = pp.add_subparsers(dest="command", required=True)
    s = psub.add_parser("review", help="show the complete plan and proposed run configuration, revision and changes")
    s.add_argument("--json", action="store_true")
    s.add_argument("plan")
    s = psub.add_parser("approve", help="record one human decision for the displayed plan and run revision")
    s.add_argument("--revision", required=True, help="revision from plan review")
    s.add_argument("--by", required=True, help="the approving human's name")
    s.add_argument("--words", required=True, help="the human's unchanged approval")
    s.add_argument("--acceptor", help="designated acceptor (defaults to the approver)")
    s.add_argument("--authority", help="unchanged grant of acceptance authority")
    s.add_argument("plan")
    for name, what in (("status", "set status only when its required evidence exists; merged belongs to finish"),
                       ("base", "move the plan's base, for example after a rebase")):
        s = psub.add_parser(name, help=what)
        s.add_argument("--note", help="why")
        s.add_argument("plan", help="the plan file")
        s.add_argument("value", metavar="VALUE" if name == "status" else "REF",
                       help="draft, approved, building, at the human gate, passed, merged or a merge-request link" if name == "status" else "a tag, branch or SHA")
    bp = top.add_parser("build", help="the build as a whole")
    s = bp.add_subparsers(dest="command", required=True).add_parser(
        "start", help="start an approved build, or show the existing assignment without restarting it")
    s.add_argument("--base", help="base ref for an unregistered plan; tasks already have a base")
    s.add_argument("--provider", help="the coordinator's provider from the approved run")
    s.add_argument("--json", action="store_true", help="print the build and its active assignments as JSON")
    s.add_argument("--worktree", metavar="PATH", help="cut the branch in a new git worktree at PATH instead of here")
    s.add_argument("--branch", metavar="NAME", help="the branch to cut, when not the plan's Status line's")
    s.add_argument("--note", help="why")
    s.add_argument("plan", help="the plan file, approved")
    hp = top.add_parser("phase", help="a phase's status, report and checks")
    hsub = hp.add_subparsers(dest="command", required=True)
    s = hsub.add_parser("start", help="set a phase in progress; refused before its waits are done, or when done, without --note")
    s.add_argument("--note", help="the reason to act against the refusal")
    s.add_argument("plan", help="the plan file")
    s.add_argument("n", type=int, help="the phase number")
    s = hsub.add_parser("report", help="record the phase's report; a second call replaces the first")
    s.add_argument("--became", required=True, help="what became true")
    s.add_argument("--skills", default="none", help="the skills read")
    s.add_argument("--interfaces", default="none", help="interfaces changed that later phases use")
    s.add_argument("--checks", default="none", help="the checks run and their result")
    s.add_argument("--check", nargs=2, action="append", metavar=("COMMAND", "OUTCOME"), default=[], help="a configured phase command and its outcome: passed or 'failed: REASON'; repeat for each")
    s.add_argument("--commit", action="append", required=True, help="a commit of this phase; repeat for each")
    s.add_argument("plan", help="the plan file")
    s.add_argument("n", type=int, help="the phase number")
    s = hsub.add_parser("done", help="verify the report's check outcomes and commits against the territory, then mark the phase done")
    s.add_argument("--note", help="why")
    s.add_argument("plan", help="the plan file")
    s.add_argument("n", type=int, help="the phase number")
    s = top.add_parser("owner", help="which running phase owns a path")
    s.add_argument("plan", help="the plan file")
    s.add_argument("path", help="a path in the tree, relative to it or absolute")
    s = top.add_parser("grant", help="let a running phase change a path outside its territory; refused if another running phase owns it")
    s.add_argument("--note", help="why")
    s.add_argument("plan", help="the plan file")
    s.add_argument("n", type=int, help="the phase number")
    s.add_argument("path", help="the path, relative to the tree")
    s = top.add_parser("decision", help="record a ruling or product call: the question, its source, the answer, why, and the cost if wrong")
    s.add_argument("--question", required=True, help="the question as asked")
    s.add_argument("--from", dest="source", required=True, help="where it came from")
    s.add_argument("--answer", required=True, help="the answer")
    s.add_argument("--why", required=True, help="why")
    s.add_argument("--cost", required=True, help="the cost if it is wrong")
    s.add_argument("--phase", type=int, help="the phase it came up in")
    s.add_argument("--by", default="orchestrator", help="who made the call (default orchestrator)")
    s.add_argument("plan", help="the plan file")
    bf = top.add_parser("brief", help="write an agent's brief to a file beside the plan and print its path")
    bsub = bf.add_subparsers(dest="command", required=True)
    s = bsub.add_parser("implementer", help="the phase's text, territory, skills, the reports it waits for, and the commands to record")
    s.add_argument("--note", help="what only the orchestrator knows")
    s.add_argument("plan", help="the plan file")
    s.add_argument("n", type=int, help="the phase number")
    s = bsub.add_parser("judge", help="the current review and E2E evidence for the gate or round; refused while the review is incomplete, or required results are missing without --note")
    s.add_argument("--note", help="what only the orchestrator knows; also the reason to brief without a result")
    s.add_argument("plan", help="the plan file")
    s = bsub.add_parser("round", help="the running round's notes file, the notes it takes, and the command to record its report")
    s.add_argument("--note", help="what only the orchestrator knows")
    s.add_argument("plan", help="the plan file")
    s = bsub.add_parser("reviewer", help="the range to review (the gate's, or the last fix's), the items the fix took, the last check run, and the commands to record")
    s.add_argument("--note", help="what only the orchestrator knows")
    s.add_argument("plan", help="the plan file")
    s = bsub.add_parser("verify", help="the cases to drive (every case at the gate; after a fix the failed ones and --cases), and the command to record")
    s.add_argument("--cases", default="", help="more cases to drive after a fix, as numbers separated by commas")
    s.add_argument("--note", help="what only the orchestrator knows")
    s.add_argument("plan", help="the plan file")
    s = bsub.add_parser("fix", help="the running fix's items with file:line and text, and the command to record its report")
    s.add_argument("--note", help="what only the orchestrator knows")
    s.add_argument("plan", help="the plan file")
    for parser in bsub.choices.values():
        parser.add_argument("--provider", help="the current provider, required for runs with executor presets")
    gp = top.add_parser("gate", help="the E2E gate")
    s = gp.add_subparsers(dest="command", required=True).add_parser(
        "start", help="write and commit the rules, compute the level, run the full checks unless this HEAD has a run")
    s.add_argument("--note", help="the reason to open the gate before every phase is done")
    s.add_argument("--check-id", help="the pending recovery identifier from status")
    s.add_argument("plan", help="the plan file")
    s = top.add_parser("finding", help="record a finding of the newest cycle: Defect, Convention, Observation, or what could not be judged")
    s.add_argument("--kind", required=True, choices=list(FINDING_KINDS))
    s.add_argument("--where", help="file:line; required except for unjudged")
    s.add_argument("--source", help="the rule or plan line it comes from")
    s.add_argument("--text", required=True, help="the finding")
    s.add_argument("--again", metavar="ID", help="a Defect a finished fix took, found again: it goes to Open")
    s.add_argument("--assignment", help="the review assignment from the brief; use with --range")
    s.add_argument("--range", help="the pinned review range from the brief; use with --assignment")
    s.add_argument("plan", help="the plan file")
    review = top.add_parser("review", help="review evidence for an assigned range")
    s = review.add_subparsers(dest="command", required=True).add_parser("complete", help="complete a review, including a clean review")
    s.add_argument("--assignment", required=True, help="the review assignment from the brief")
    s.add_argument("--range", required=True, help="the pinned BASE..HEAD from the brief")
    s.add_argument("plan", help="the plan file")
    s = top.add_parser("result", help="record a Done case's result; passed and failed need a capture")
    s.add_argument("--case", required=True, type=int, help="the Done item's number")
    s.add_argument("--outcome", required=True, choices=["passed", "failed", "not-reached"])
    s.add_argument("--capture", help="a capture path, or the command's output")
    s.add_argument("--detail", help="what was seen when failed, why when not reached")
    s.add_argument("--width", help="the width driven")
    s.add_argument("--do", help="default: the Done item's text before the arrow")
    s.add_argument("--see", help="default: the Done item's text after the arrow")
    s.add_argument("--cycle", help="the check cycle from the brief; use with --head")
    s.add_argument("--head", help="the commit driven from the brief; use with --cycle")
    s.add_argument("plan", help="the plan file")
    xp = top.add_parser("fix", help="a fix of the newest cycle: takes every open item, is capped per cycle, re-runs the full checks when done")
    xsub = xp.add_subparsers(dest="command", required=True)
    s = xsub.add_parser("start", help="take every open item; refused while a fix runs or at the cycle's cap")
    s.add_argument("plan", help="the plan file")
    s = xsub.add_parser("report", help="record the fix's report; a second call replaces the first")
    s.add_argument("--became", required=True, help="what became true")
    s.add_argument("--skills", default="none", help="the skills read")
    s.add_argument("--interfaces", default="none", help="interfaces changed")
    s.add_argument("--checks", default="none", help="the checks run and their result")
    s.add_argument("--commit", action="append", default=[], help="a commit of this fix; repeat for each; none when the fix changed nothing")
    s.add_argument("plan", help="the plan file")
    s = xsub.add_parser("done", help="write and commit the rules, run the full checks at the new HEAD, mark what survived")
    s.add_argument("--check-id", help="the pending recovery identifier from status")
    s.add_argument("plan", help="the plan file")
    s = top.add_parser("verdict", help="the judge's verdict on the newest cycle: a decision for every Open entry and Convention, each --decide action one of let-through, round or question; the first one writes .judge.md and alone takes --predicted, --predict and --engine. A round verdict past the cap, or on an early-stop sign, records the stop and opens no round")
    s.add_argument("kind", choices=["pass", "round", "question", "evidence-owed"])
    s.add_argument("--owed", choices=EVIDENCE_ROLES, help="evidence-owed: who owes the evidence; the verdict takes no decisions")
    s.add_argument("--case", type=int, action="append", default=[], help="evidence owed by Verify: Done case to drive again; repeat for each case")
    s.add_argument("--evidence-note", help="the reason to judge with missing gate results; recorded on the acceptance page")
    s.add_argument("--report", required=True, help="what was let through and why, in the judge's words")
    s.add_argument("--decide", nargs=3, action="append", metavar=("ID", "ACTION", "REASON"), help="let-through, round or question for an Open entry or a Convention; repeat for each")
    s.add_argument("--note", nargs=2, action="append", metavar=("TEXT", "CAUSE"), help="a round verdict's note in the judge's words, with its cause; repeat for each")
    s.add_argument("--question", help="the question for the human, for a question verdict or beside round notes")
    s.add_argument("--predicted", choices=["pass", "round"], help="the human's verdict as predicted; the first verdict only")
    s.add_argument("--predict", nargs=2, action="append", metavar=("TEXT", "CAUSE"), help="a note the human will make, with its cause; the first verdict only, repeat for each")
    s.add_argument("--engine", help="a nonblank single-line engine identifier; the first verdict only")
    s.add_argument("plan", help="the plan file")
    lp = top.add_parser("land", help="rewrite the branch into the shape's commits: `land PLAN` lands the shape file; `land draft|accept|revert` start it, keep a hook's change, or return to the backup")
    lsub = lp.add_subparsers(dest="command", metavar="[draft|accept|revert]")
    for name, what in (("draft", "write the shape file: the last shape on a re-land, else one commit holding every path"),
                       ("accept", "keep the commits a hook changed; --note says why and goes on the page"),
                       ("revert", "reset the branch to the backup and record a stop"),
                       ("now", "land the shape file (what `land PLAN` runs)")):
        s = lsub.add_parser(name, help=what)
        if name in ("accept", "revert"):
            s.add_argument("--note", help="why" if name == "revert" else "why the change stays (required)")
        s.add_argument("plan", help="the plan file")
    s = top.add_parser("page", help="record and print the guide to the landed result, or read the current recorded guide")
    guide_args = s.add_mutually_exclusive_group(required=True)
    guide_args.add_argument("--guide", "--note", help="the guide as Markdown")
    guide_args.add_argument("--guide-file", help="the UTF-8 Markdown file containing the guide")
    guide_args.add_argument("--show", action="store_true", help="print the current recorded guide without changing the page")
    s.add_argument("--message", help="the merge message, or the request's title; required unless the run ends in ff-only")
    s.add_argument("plan", help="the plan file")
    s = top.add_parser("accept", help="record authorized acceptance of the current page and set passed")
    s.add_argument("--by", required=True)
    s.add_argument("--words", required=True)
    s.add_argument("plan")
    if routing:  # Pinned older releases still parse the two consent commands.
        sp = top.add_parser("summary")
        s = sp.add_subparsers(dest="command", required=True).add_parser("approve")
        s.add_argument("--file", required=True)
        s.add_argument("--by", required=True)
        s.add_argument("--words", required=True)
        s.add_argument("--acceptor")
        s.add_argument("--authority")
        s.add_argument("plan")
    np_ = top.add_parser("note", help="the human's notes, in their words; code numbers them and renders the notes file")
    nsub = np_.add_subparsers(dest="command", required=True)
    s = nsub.add_parser("add", help="record a note: its words and its cause (task is a verdict: listed, never built)")
    s.add_argument("--text", required=True, help="the note in the human's words")
    s.add_argument("--cause", required=True, choices=CAUSES)
    s.add_argument("plan", help="the plan file")
    s = nsub.add_parser("edit", help="change an open note's words or cause, or mark the source of a note a round took")
    s.add_argument("--text")
    s.add_argument("--cause", choices=CAUSES)
    s.add_argument("--source", help="P<n>, a note the judge predicted, or missed")
    s.add_argument("plan", help="the plan file")
    s.add_argument("n", type=int, help="the note's number")
    s = nsub.add_parser("drop", help="drop an open note")
    s.add_argument("plan", help="the plan file")
    s.add_argument("n", type=int, help="the note's number")
    ro = top.add_parser("round", help="a round: the notes built by a new implementer, then re-checked as a cycle of its own")
    rosub = ro.add_subparsers(dest="command", required=True)
    s = rosub.add_parser("start", help="take the judge's notes when the last verdict ordered a round, else every open note; the human's round starts a new count")
    s.add_argument("--conflict", metavar="WHAT", help="a round for a conflict at finish: takes no notes, starts a new count, and sets a passed plan back to building")
    s.add_argument("plan", help="the plan file")
    s = rosub.add_parser("report", help="record the round's report; a second call replaces the first")
    s.add_argument("--became", required=True, help="what became true")
    s.add_argument("--skills", default="none", help="the skills read")
    s.add_argument("--interfaces", default="none", help="interfaces changed")
    s.add_argument("--checks", default="none", help="the checks run and their result")
    s.add_argument("--commit", action="append", default=[], help="a commit of this round; repeat for each; none when the round changed nothing")
    s.add_argument("plan", help="the plan file")
    s = rosub.add_parser("done", help="refused while a note of the human's has no source; writes and commits the rules, runs the full checks at the new HEAD, completes the notes file")
    s.add_argument("--check-id", help="the pending recovery identifier from status")
    s.add_argument("plan", help="the plan file")
    s = top.add_parser("finish", help="end the run as the run file's [finish] says: merge locally, or push the branch and open the merge request by the remote's forge; later, check the request and set merged")
    s.add_argument("--merged", action="store_true", help="the request is merged (GitLab or an unknown host, where code cannot ask)")
    s.add_argument("--json", action="store_true", help="show the integration result, pending cleanup and next actions as JSON")
    s.add_argument("plan", help="the plan file, passed or a merge request's link")
    rp = top.add_parser("run", help="the run file beside the plan: its path need not exist yet")
    rsub = rp.add_subparsers(dest="command", required=True)
    new_help = ("snapshot defaults for an interrupted task entry; start new tasks with runweld task start" if standalone else
                "copy the newest run file in the plan's directory, else the shipped example")
    s = rsub.add_parser("new", help=new_help + "; refused if the file exists")
    s.add_argument("plan", help="the plan file, which need not exist")
    ep = top.add_parser("executor", help="select the current provider's primary/secondary executors")
    s = ep.add_subparsers(dest="command", required=True).add_parser("show", help="use project settings before plan approval and the approved snapshot afterward")
    s.add_argument("--provider", required=True, help="the current provider's opaque identifier")
    s.add_argument("--json", action="store_true")
    s.add_argument("plan", nargs="?", help="omit to read current project profiles for planning helpers")
    s = rsub.add_parser("check", help="print every problem of the run file, silent when it is sound")
    s.add_argument("plan", help="the plan file, which need not exist")
    if routing:
        s = rsub.add_parser("approve")
        s.add_argument("--by", required=True)
        s.add_argument("--words", required=True)
        s.add_argument("plan")
    s = rsub.add_parser("show", help="the run file's values: the approved ones once the plan is approved, with any drift")
    s.add_argument("--json", action="store_true", help="print as JSON: run, approved, drift")
    s.add_argument("plan", help="the plan file, which need not exist")
    from runweld_release import GUIDE_COMMANDS
    argv = list(argv)
    p.epilog = "Run a bare instruction command to print its guide: " + ", ".join(GUIDE_COMMANDS) + "."
    for name in GUIDE_COMMANDS:
        if name not in top.choices:
            parser_for_guide = top.add_parser(name, help=f"print {name} instructions")
            parser_for_guide.add_argument("--plan", help="use a task's pinned release")
            parser_for_guide.set_defaults(group="guide", guide=name)
            if name == "browser-test":
                parser_for_guide.add_argument("browser_args", nargs=argparse.REMAINDER)
            if standalone and name in ("grill", "prototype", "bug"):
                events = parser_for_guide.add_subparsers(dest="event", metavar="{start,save,done,skip}")
                for event in ("start", "save", "done", "skip"):
                    stage = events.add_parser(event)
                    stage.add_argument("plan", nargs="?", help="plan path (omit in its task worktree)")
                    discovery_options(stage)
                    stage.set_defaults(group="discovery", stage="reproduce" if name == "bug" else name)
    if argv and argv[0] in GUIDE_COMMANDS and (len(argv) == 1 or argv[1] == "--plan"):
        guide = type(p)(prog=f"{p.prog} {argv[0]}", description=f"Print {argv[0]} instructions")
        guide.add_argument("--plan", help="use a task's pinned release")
        if argv[0] == "browser-test":
            guide.add_argument("browser_args", nargs=argparse.REMAINDER)
        guide.set_defaults(group="guide", guide=argv[0])
        return guide, guide.parse_args(argv[1:])
    if argv[:1] == ["land"] and argv[1:2] and argv[1] not in ("draft", "accept", "revert", "now", "-h", "--help"):
        argv.insert(1, "now")
    a = p.parse_args(argv)
    if a.group == "land" and not a.command:
        lp.error("a plan file, or draft|accept|revert|now and a plan file, is required")
    return p, a


def print_reference(bundle, resource):
    from runweld_release import release_manifest
    if resource not in release_manifest(bundle, bundle.name)["files"] or Path(resource).suffix not in (".md", ".toml"):
        raise Refuse("unknown-reference", f"{resource!r} is not a readable release resource", "copy an exact resource path from the instruction")
    print((bundle / resource).read_text(encoding="utf-8").rstrip())
    return 0


def print_guide(name, browser_args=(), plan=None):
    from runweld_release import ROLES
    root = Path(PACKAGE)
    if name == "browser-test" and browser_args:
        return subprocess.run(["node", str(root / "workflow/browser-test/tab.mjs"), *browser_args]).returncode
    catalog = workflow_catalog()
    stage = catalog["stages"].get(name, {})
    references = stage.get("references")
    if name == "bug" and standalone_bundle():
        references = {
            "workflow/bug/references/root-cause-tracing.md": "Trace an unknown cause",
            "workflow/bug/references/condition-based-waiting.md": "Investigate a real timing race",
            "workflow/bug/references/defense-in-depth.md": "Place validation at the right boundaries",
        }
    directory = root / "workflow" / name
    paths = [root / "agents" / f"{name}.md"] if name in ROLES else []
    if directory.is_dir():
        paths.append(directory / "GUIDE.md")
        paths.extend(sorted(path for path in (directory / "references").glob("*")
                            if path.suffix in (".md", ".toml") and path.relative_to(root).as_posix() not in (references or {})))
    paths.extend(root / path for path in stage.get("inputs", []))
    paths.extend(root / path for path in stage.get("roles", {}).values())
    paths.extend(root / path for path in catalog["shared"])
    print(f"runweld {name}\n")
    for path in dict.fromkeys(paths):
        if path.suffix not in (".md", ".toml"):
            continue
        body = path.read_text(encoding="utf-8")
        if body.startswith("---\n"):
            body = body.split("\n---\n", 1)[-1]
        print(body.strip(), end="\n\n")
    for condition, dependency in stage.get("when", {}).items():
        commands = [Path(path).parent.name for path in dependency["inputs"] if path.endswith("/GUIDE.md")]
        print(f"For {condition}, {dependency['role']} uses " + ", ".join(f"`runweld {cmd}`" for cmd in commands) + ".")
    if references and standalone_bundle():
        print("References when needed:")
        for resource, reason in references.items():
            argv = [*cli_argv(plan), "reference", resource, *(["--plan", str(plan)] if plan else [])]
            print(f"  {reason} — {shlex.join(argv)}")
    elif references:
        for resource in references:
            print((root / resource).read_text(encoding="utf-8").strip(), end="\n\n")
    return 0


def agent_help(bundle):
    from runweld_release import GUIDE_COMMANDS
    print(f"Runweld {bundle.name}\n")
    print("Run `runweld next` in a Git checkout or task worktree. Add `--json` for machine-readable actions.")
    print("If the project isn't initialized, `runweld init` previews and saves its settings and executor pair.")
    print("Start with `runweld task start ID --goal TEXT` (add `--bug` for a reproduction), or resume with `runweld next ID`.")
    print("From a task worktree, `runweld next` finds the assignment and its release without an ID.")
    print("\nWorkflow:")
    catalog = workflow_catalog()
    for stage in catalog["order"]:
        entry = catalog["stages"][stage]
        print(f"  {entry['label']} — {entry.get('purpose', stage)}")
    print()
    print("Instruction commands (add --plan PLAN to select a task's release):")
    print("\n".join(f"  runweld {name}" for name in GUIDE_COMMANDS))
    print("Use `runweld reference RELEASE_PATH --plan PLAN` for conditional material named by an instruction.")


def main(*, current_task=None, next_release=None):
    from runweld_release import ReleaseError
    bundle = standalone_bundle()
    p, a = parse_cli(sys.argv[1:] or (["--help"] if bundle else []), standalone=bundle is not None,
                     version=bundle.name if bundle else None)

    def transition(result, *, stream=None):
        if bundle is not None and not result:
            try:
                facts = cmd_status(a.plan, False, os.getcwd(), as_data=True)
            except (Refuse, ReleaseError) as error:
                print(f"Recorded the transition, but could not read the next action: {error}", file=sys.stderr)
                return result
            with contextlib.redirect_stdout(stream) if stream else contextlib.nullcontext():
                show_next(facts["workflow"]["actions"])
        return result

    try:
        plan_arg = getattr(a, "plan", None)
        if bundle is not None:
            from runweld_release import command_plan, run_pin, update_installation
            selected_plan = command_plan(a, Path.cwd())
            required = run_pin(selected_plan) if selected_plan else None
            release = next_release or bundle.name
            if required is not None and required != release:
                raise ReleaseError(f"this run selects {required}, not {release}; use `runweld` without a release override")
            if a.group == "update":
                update_installation(bundle.parents[1], a.scope, a.version)
                return 0
            if a.group == "init":
                try:
                    return cmd_init(bundle, a)
                except (EOFError, KeyboardInterrupt):
                    raise ReleaseError("initialization cancelled; rerun `runweld init` to continue") from None
                except (OSError, Fail) as error:
                    raise ReleaseError(f"initialization could not finish: {error}; correct the issue and rerun `runweld init`") from None
            if a.group == "discovery" or a.group == "task" and a.command == "stage":
                return cmd_discovery(selected_plan, a)
            if a.group == "task" and a.command not in ("setup", "stage"):
                return cmd_task(bundle, a)
            if a.group == "task" and a.command == "setup":
                return cmd_task_setup(a.plan, reproduction=a.reproduction, preview=a.preview)
            if a.group == "next":
                return cmd_next(bundle, a, selected_plan, next_release)
            if a.group == "path":
                return cmd_path(a.area)
            if a.group == "reference":
                return print_reference(bundle, a.resource)
            if a.group == "handoff":
                return herdr_handoff(selected_plan, a)
            if a.group == "help":
                if a.topic == "agents":
                    agent_help(bundle)
                else:
                    p.print_help()
                return 0
        if a.group == "guide":
            return print_guide(a.guide, getattr(a, "browser_args", ()), plan=selected_plan if bundle else None)
        if a.group == "spec":
            if a.command in ("list", "show"):
                return read_spec(a.command, getattr(a, "id", None))
            task = task_for(a.plan) if bundle is not None else None
            if task:
                ensure_task_tree(task, plan_root(plan_paths(a.plan)[0]))
                state = load_state(task["plan"])
                if a.command == "check" and (state is None or state["status"] in ("draft", "approved")):
                    require_discovery(task)
                    head, _ = read_plan(task["plan"])
                    explicit = git("rev-parse", "--verify", "-q", "--end-of-options", f"{a.base}^{{commit}}",
                                   cwd=task["tree"], check=False).stdout.strip() if a.base else task["base"]
                    if base_of(head, None) != task["base"] or explicit != task["base"]:
                        raise Refuse("task-base", f"the registered base is {task['base']}", "use that SHA in Status and omit --base")
                    a.base = task["base"]
            return run(a.command, task["plan"] if task else a.plan, a.base, cwd=task["tree"] if task else None)
        if plan_arg and a.group not in ("run", "spec", "executor") and not os.path.isfile(plan_arg):
            read_plan(plan_paths(plan_arg)[0])
        if a.group == "accept":
            return transition(cmd_accept(a.plan, a))
        if a.group == "run":
            return cmd_run(a.command, a.plan, getattr(a, "json", False))
        if a.group == "executor":
            return cmd_executor(a.plan, a.provider, a.json)
        if a.group == "approve":
            return cmd_approve(a.plan, a.json)
        if a.group == "status":
            return cmd_status(a.plan, a.json, os.getcwd(), a.current, a.provider, current_task=current_task)
        if a.group == "workflow":
            return cmd_workflow(a.json, a.stage)
        if a.group == "plan":
            if a.command == "review":
                return cmd_plan_review(a.plan, a.json)
            if a.command == "approve":
                return transition(cmd_plan_approval(a.plan, a))
            return cmd_plan(a.command, a.plan, a.value, a.note)
        if a.group == "build":
            return cmd_build_start(a.plan, a.base, a.worktree, a.branch, a.note, a.provider, a.json)
        if a.group == "phase":
            return transition({"start": lambda: cmd_phase_start(a.plan, a.n, a.note), "report": lambda: cmd_phase_report(a.plan, a.n, a),
                               "done": lambda: cmd_phase_done(a.plan, a.n, a.note)}[a.command]())
        if a.group == "owner":
            return cmd_owner(a.plan, a.path)
        if a.group == "grant":
            return cmd_grant(a.plan, a.n, a.path, a.note)
        if a.group == "gate" or (a.group in ("fix", "round") and a.command == "done"):
            with check_lease(a.plan) as lease:
                result = (cmd_gate_start(a.plan, a.note, lease, a.check_id) if a.group == "gate"
                          else (fix_done if a.group == "fix" else round_done)(a.plan, lease, a.check_id))
            return transition(result)
        if a.group == "finding":
            return cmd_finding(a.plan, a)
        if a.group == "review":
            return transition(cmd_review(a.plan, a))
        if a.group == "result":
            return transition(cmd_result(a.plan, a))
        if a.group == "fix":
            return transition(cmd_fix(a.plan, a))
        if a.group == "verdict":
            return transition(cmd_verdict(a.plan, a))
        if a.group == "note":
            return transition(cmd_note(a.plan, a))
        if a.group == "round":
            return transition(cmd_round(a.plan, a))
        if a.group == "land":
            result = cmd_land(a.plan, a.command, getattr(a, "note", None))
            return result if a.command == "draft" else transition(result)
        if a.group == "finish":
            return finish_and_report(a.plan, a.merged, a.json) if bundle is not None or a.json else cmd_finish(a.plan, a.merged)
        if a.group == "page":
            result = cmd_page(a.plan, a)
            return result if a.show else transition(result, stream=sys.stderr)
        if a.group == "decision":
            return cmd_decision(a.plan, a)
        if a.group == "brief":
            return cmd_brief(a.plan, a.command, getattr(a, "n", None), a.note, [int(x) for x in getattr(a, "cases", "").split(",") if x.strip()], a.provider)
    except ReleaseError as error:
        print(f"runweld: {error}", file=sys.stderr)
        return 1
    except Refuse as e:
        for code, message, fix in e.diags:
            print(f"{code}: {message} — fix: {fix}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
