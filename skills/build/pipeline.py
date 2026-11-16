#!/usr/bin/env python3
"""The pipeline's CLI: the plan parser and the project's rules in docs/spec/.

Usage: pipeline.py spec check [--base REV] PLAN
       pipeline.py spec write [--base REV] PLAN
       pipeline.py spec list
       pipeline.py spec show ID
       pipeline.py approve [--json] PLAN
       pipeline.py status [--json] [PLAN]
       pipeline.py plan status [--note TEXT] PLAN VALUE
       pipeline.py plan base [--note TEXT] PLAN REF
       pipeline.py build start --base REF [--worktree PATH] [--note TEXT] PLAN
       pipeline.py phase start|done [--note TEXT] PLAN N
       pipeline.py phase report --became T --commit SHA [...] PLAN N
       pipeline.py owner PLAN PATH
       pipeline.py grant [--note TEXT] PLAN N PATH
       pipeline.py decision --question Q --from S --answer A --why W --cost C PLAN
       pipeline.py brief implementer PLAN N | brief judge|round PLAN   [--note TEXT]
       pipeline.py verdict pass|round|question PLAN --report T [--decide ID ACTION REASON] [--note T CAUSE]
       pipeline.py note add|edit|drop PLAN ...
       pipeline.py round start|report|done PLAN
       pipeline.py run new|check PLAN | run show [--json] PLAN

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

run new copies the newest run file beside the plan (else the shipped example) to
`<slug>.run.toml`; run check prints every problem as `<code>: … — fix: …`; run show
prints the approved values, or the file's before approval, and any drift.

list prints every area (`<area> — <title>`), its description indented under it, and its rules, indented
(`  <area>#<rule> — <statement>`), from the working tree. show prints the rule
`<area>#<rule>` (heading, Why, scenarios), then each archive record whose Spec
section names it, newest file name first: `## archive/<file> — <plan title>`
and that section's entry for the rule. An ID that is not a rule is
`pipeline.py spec: no rule <id>` on stderr, exit 1.

approve compiles a plan into `<slug>.json` (the state) after a strict check, whose
problems are `<plan>:<line>: <message>`, exit 1; it renders the code-owned lines
back into the plan and the plan's row in its epic, and adopts a plan that has no
state as its file stands. approve also requires the draft's run file
(`<slug>.run.toml`, see `run check`) and records its values under `run`; a plan
adopted without one goes on without. Every write refuses (`<code>: <message> — fix: <fix>`,
exit 1) while the plan file differs from its last render. status prints one plan
or all; plan status and plan base change the plan's code-owned fields. Library
use: `writing(plan)` yields the locked state and saves and renders on exit;
`set_plan`, `set_phase`, `record` and `ready_phases` work on it.
"""

import argparse
import contextlib
import datetime
import errno
import fcntl
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import shutil
import socket
import tempfile
import tomllib

HISTORY = "This is history; the rules that hold now are in `docs/spec/`."
README = (
    "# Spec\n\n"
    "The rules this product must keep, one file per area. The script writes these\n"
    "files from plans; a rule is changed through a plan or `dev-skills:spec`, not by\n"
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


def tree_at(rev):
    """docs/spec/ as committed at rev: {rel path: text}. An unborn HEAD has none."""
    if git("rev-parse", "--verify", "-q", f"{rev}^{{commit}}", check=False).returncode:
        if rev == "HEAD":
            return {}
        raise Fail(f"unknown base {rev}")
    names = git("ls-tree", "-r", "--full-tree", "--name-only", rev, "--", "docs/spec/").stdout.split("\n")
    return {p[len("docs/spec/"):]: git("show", f"{rev}:{p}").stdout for p in names if p}


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
        elif last and line.startswith((" ", "\t")) and line.strip():
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


def run(command, plan, given_base):
    try:
        root = git("rev-parse", "--show-toplevel").stdout.strip()
    except Fail:
        print("pipeline.py spec: not inside a git repository", file=sys.stderr)
        return 1
    try:
        with open(plan, encoding="utf-8") as f:
            plan_lines = f.read().splitlines()
    except OSError as e:
        print(f"pipeline.py spec: {e}", file=sys.stderr)
        return 2
    name = os.path.basename(plan)
    base_rev = base_of(plan_lines, given_base)
    try:
        tree = tree_at(base_rev)
        head = tree_at("HEAD")
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
        # a record without Done is an old format: the plan's own Done stands in
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


def plan_paths(plan):
    """-> (plan .md, state .json, lock), all absolute."""
    md = os.path.abspath(plan)
    if not md.endswith(".md"):
        raise Refuse("bad-plan", f"{plan} is not a .md file", "pass the plan file")
    return md, md[:-3] + ".json", md[:-3] + ".json.lock"


def is_plan_file(fn):
    """A plan's own .md: not its notes, judge file, gate log or briefs."""
    return fn.endswith(".md") and not re.search(r"\.(notes|judge|gate-log|brief-[\w-]+)\.md$", fn)


def plan_root(md):
    r = git("rev-parse", "--show-toplevel", check=False, cwd=os.path.dirname(md))
    if r.returncode:
        raise Refuse("no-repo", f"{md} is not inside a git repository", "keep plans in the project's .ai-workflow/plans/")
    return r.stdout.strip()


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
    try:
        text = open(md, encoding="utf-8").read()
    except OSError as e:
        raise Refuse("no-plan", str(e), "pass an existing plan file")
    return split_gate(text.split("\n"))


def head_hash(head):
    return hashlib.sha256("\n".join(head).encode()).hexdigest()


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


def epic_row(root, path, row):
    """-> (lines of the epic file, index of its row in the `## Plans` table or None), or (None, None) without the file."""
    try:
        lines = open(os.path.join(root, path), encoding="utf-8").read().split("\n")
    except OSError:
        return None, None
    start, body = sections(lines).get("Plans", (0, []))
    mask = fenced(body)
    at = next((k for k, l in enumerate(body) if not mask[k] and re.match(rf"^\|\s*{row}\s*\|", l)), None)
    return lines, None if at is None else start - 1 + at


def parse_plan(lines, root):
    """The plan's lines (as far as the CLI reads them) -> (plan dict, problems [(line, message)])."""
    problems = []
    bad = lambda n, m: problems.append((n, m))
    P = {"title": None, "status": None, "branch": None, "base": None, "epic": None, "level": None, "phases": []}
    mask = fenced(lines)
    for l, f in zip(lines, mask):
        if l.startswith("# ") and not f:
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
            efile, erow = epic_row(root, m[1], m[2])
            if efile is None:
                bad(n, f"epic file {m[1]} does not exist")
            elif erow is None:
                bad(n, f"epic {m[1]} has no table row {m[2]}")
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
        parse_phases(*secs["Phases"], root, P, bad)
    return P, problems


def parse_phases(start, body, root, P, bad):
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
            if "/" in sk or sk.endswith(".md"):
                if not (os.path.exists(os.path.join(root, sk)) or os.path.exists(os.path.expanduser(sk))):
                    bad(ln["Skills"], f"phase {ph['n']}: skill {sk} does not exist")
            elif not re.fullmatch(r"[\w.:-]+", sk):
                bad(ln["Skills"], f"phase {ph['n']}: {sk!r} is neither a SKILL.md path nor a skill name")
        ph["spec"] = paths_of(f.get("Spec", ""))
        for sp in ph["spec"]:
            if not os.path.exists(os.path.join(root, sp)):
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
    d = os.path.dirname(md)
    out = []
    for fn in sorted(os.listdir(d)):
        full = os.path.join(d, fn)
        if not is_plan_file(fn) or full == md:
            continue
        try:
            head = split_gate(open(full, encoding="utf-8").read().split("\n"))[0]
            P, _ = parse_plan(head, root)
            st = json.load(open(full[:-3] + ".json")) if os.path.exists(full[:-3] + ".json") else None
        except (OSError, ValueError):
            continue
        status = st["status"] if st else P["status"]
        if status in LIVE:
            out.append((fn[:-3], status, P))
    return out


# -- state file, lock, render

@contextlib.contextmanager
def locked(plan):
    with open(plan_paths(plan)[2], "a") as lf:
        fcntl.flock(lf, fcntl.LOCK_EX)
        yield


def load_state(plan):
    js = plan_paths(plan)[1]
    if not os.path.exists(js):
        return None
    try:
        return json.load(open(js, encoding="utf-8"))
    except ValueError as e:
        raise Refuse("bad-state", f"{js} is not valid JSON ({e})", "restore it from git or approve the plan again after deleting it")


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
    for path, text in ((md, "\n".join(head + tail)), (js, json.dumps(st, indent=2, ensure_ascii=False) + "\n")):
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".pipeline-")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, path)
    sync_epic(plan_root(md), md, st)
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


def drift_diags(plan, st, head):
    """What differs between the file and its last render, as Refuse diagnostics."""
    if head_hash(head) == st.get("render_hash"):
        return []
    owned = code_owned(st, head)
    if owned:
        return [("drift", f"{plan}:{n}: `{t}` was edited by hand", f"restore it, or change it with `{c}`") for n, t, c in owned]
    return [("drift", f"{plan} differs from its last render", f"run `pipeline.py approve {plan}` to compile the edit")]


@contextlib.contextmanager
def writing(plan):
    """Lock the plan's state, refuse on drift, yield the state; saves and renders on exit.

    Call set_plan / set_phase inside; an exception leaves both files as they were.
    """
    md = plan_paths(plan)[0]
    with locked(plan):
        st = load_state(plan)
        if st is None:
            raise Refuse("not-compiled", f"{plan} has no state file", f"run `pipeline.py approve {plan}`")
        head, tail = read_plan(md)
        diags = drift_diags(plan, st, head)
        if diags:
            r = Refuse(*diags[0])
            r.diags = diags
            raise r
        yield st
        save(plan, st, head, tail)


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
    "checks": {"phase": "list", "full": "list", "dev": "str", "url": "str"},
    "isolation": {"worktree": "bool", "port": "bool", "data_dir": "bool"},
}
RUN_OPTIONAL = {("checks", "dev"), ("checks", "url")}
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
        return isinstance(v, str)
    return isinstance(v, list) and all(isinstance(x, str) for x in v)


def read_run(plan):
    """-> (values, []) or (None, [(code, message, fix)]); the file is read as written."""
    path = run_path(plan)
    if not os.path.exists(path):
        return None, [("no-run-file", f"{path} does not exist", "write it with `dev-skills:run-file`, or copy one with `pipeline.py run new`")]
    try:
        with open(path, "rb") as f:
            v = tomllib.load(f)
    except (tomllib.TOMLDecodeError, OSError, UnicodeDecodeError) as e:
        return None, [("run-bad-toml", f"{path} is not valid TOML ({e})", "fix the syntax")]
    out = []
    for sec in v:
        if sec not in RUN_SECTIONS and sec != "run":
            out.append(("run-unknown-section", f"[{sec}] is not a section of the run file", "use [finish], [checks], [isolation] or [run]"))
    for sec, keys in RUN_SECTIONS.items():
        t = v.get(sec, {})
        if not isinstance(t, dict):
            out.append(("run-bad-type", f"[{sec}] must be a table", f"write [{sec}] as a section"))
            continue
        for k in t:
            if k not in keys:
                out.append(("run-unknown-key", f"[{sec}] {k} is not a key of the section", "use only: " + ", ".join(keys)))
        for k, kind in keys.items():
            if k not in t:
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
    checks, iso = v.get("checks", {}), v.get("isolation", {})
    if isinstance(checks, dict) and isinstance(iso, dict):
        for k, x in checks.items():
            for s in x if isinstance(x, list) else [x]:
                for ph in sorted(set(PLACEHOLDER.findall(s)) if isinstance(s, str) else []):
                    if iso.get(ph) is not True:
                        out.append(("run-bad-placeholder", f"[checks] {k} uses {{{ph}}}, but [isolation] {ph} is not true", f"set `{ph} = true` in [isolation], or drop the placeholder"))
    return (None, out) if out else (v, [])


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
    """What differs between the file and the values `approve` recorded: [(code, message, fix)]."""
    if "run" not in st:
        return []
    fix = f"run `pipeline.py approve {plan}` to take the change, or restore the file"
    v, probs = read_run(plan)
    if v is None:
        return [("run-drift", f"{run_path(plan)} no longer passes `run check` ({probs[0][1]}); the approved values stand", fix)]
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


def allocate(plan, md, st, have=None):
    """What [isolation] asks for and `have` lacks: {"port": n, "data_dir": path}."""
    iso, new = st.get("run", {}).get("isolation", {}), {}
    if iso.get("port") and "port" not in (have or {}):
        new["port"] = free_port(plan, md)
    if iso.get("data_dir") and "data_dir" not in (have or {}):
        new["data_dir"] = os.path.join(os.path.dirname(os.path.abspath(md)), plan_slug(st) + ".data")
    return new


def free_port(plan, md):
    """The first port of PORTS that nothing listens on and no live plan holds."""
    d = os.path.dirname(md)
    held = set()
    for name, _, _ in other_plans(plan_root(md), md):
        o = load_state(os.path.join(d, name + ".md"))
        held.add(((o or {}).get("alloc") or {}).get("port"))
    for p in PORTS:
        if p in held:
            continue
        if all(bindable(fam, addr, p) for fam, addr in PROBES):
            return p
    raise Refuse("no-port", f"no free port in {PORTS.start}-{PORTS[-1]}", "stop a plan that holds one, or free a port")


def cmd_run(command, plan, as_json):
    path = run_path(plan)
    if command == "new":
        if os.path.exists(path):
            raise Refuse("run-exists", f"{path} already exists", "edit it, or pick another plan name")
        d = os.path.dirname(path)
        runs = [os.path.join(d, f) for f in os.listdir(d) if f.endswith(".run.toml")] if os.path.isdir(d) else []
        src = max(runs, key=os.path.getmtime) if runs else os.path.normpath(EXAMPLE)
        os.makedirs(d, exist_ok=True)
        with open(src, encoding="utf-8") as f:
            text = f.read()
        if not runs:
            text = re.sub(r"(?ms)^(\[run\][^\n]*\n).*\Z", r"\1", text)  # keys of the shipped example are samples
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        print(f"run new: {path} (copied from {src})")
        return 0
    v, probs = read_run(plan)
    if command == "check":
        if probs:
            raise refuse_all(probs)
        return 0
    st = load_state(plan)
    if st is not None and "run" in st:
        v, drift = fill(st["run"], st.get("alloc")), run_drift(plan, st)
    elif probs:
        raise refuse_all(probs)
    else:
        drift = []
    if as_json:
        print(json.dumps({"run": v, "approved": st is not None and "run" in st, "alloc": (st or {}).get("alloc"), "drift": [f"{m} — fix: {f}" for _, m, f in drift]}, ensure_ascii=False))
        return 0
    for sec, t in v.items():
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

def cmd_approve(plan, as_json):
    md = plan_paths(plan)[0]
    root = plan_root(md)
    head, tail = read_plan(md)
    P, problems = parse_plan(head, root)
    if problems:
        print("\n".join(f"{plan}:{n}: {m}" for n, m in sorted(problems)))
        return 1
    derived = ("title", "territory", "skills", "spec", "waits", "waits_text")
    with locked(plan):
        st = load_state(plan)
        if st is None:
            how = "approved" if P["status"] == "draft" else "adopted"
            st = {"version": 1, "plan": os.path.basename(md), "status": "approved" if how == "approved" else P["status"],
                  "branch": P["branch"], "base": P["base"], "history": [], "phases": []}
            if how == "adopted" and (t := branch_tree(root, P["branch"])):
                st["tree"] = t
            record(plan, st, how, P["status"], st["status"], None if how == "approved" else "a plan without state, taken as its file stood")
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
        if probs and (had or how == "approved" or os.path.exists(run_path(plan))):
            raise refuse_all(probs)
        facts = []
        if values is not None:
            if had and (ch := run_changes(st["run"], values)):
                record(plan, st, "run file", None, "changed", ", ".join(f"{x} {k}" for x, k in ch))
            st["run"] = values
            if st["status"] != "approved":
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
    for name, status, other in other_plans(root, md):
        hit = sorted({t for p in other["phases"] for t in p["territory"] for m in mine if overlaps(t, m)})
        if hit:
            over.append({"plan": name, "status": status, "paths": hit})
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


def summary(plan, st, head):
    """-> the dict `status --json` prints."""
    return {**{k: st.get(k) for k in ("title", "status", "branch", "base", "epic", "level", "phases", "history", "decisions")},
            "done": st.get("done", []), "verdicts": st.get("verdicts", []), "rounds": st.get("rounds", []), "notes": st.get("notes", []), "cycles": [{**c, "list": items(c)} for c in st.get("cycles", [])], "plan": plan_slug(st), "ready": ready_phases(st), "tree": tree_fact(plan, st), "alloc": st.get("alloc"),
            "drift": [f"{m} — fix: {f}" for _, m, f in drift_diags(plan, st, head) + run_drift(plan, st)]}


def cmd_status(plan, as_json, cwd):
    if plan is None:
        root = git("rev-parse", "--show-toplevel", check=False, cwd=cwd)
        if root.returncode:
            raise Refuse("no-repo", "not inside a git repository", "run it in the project")
        d = os.path.join(root.stdout.strip(), ".ai-workflow", "plans")
        names = [f for f in sorted(os.listdir(d)) if is_plan_file(f)] if os.path.isdir(d) else []
        rows = []
        for fn in names:
            full = os.path.join(d, fn)
            st = load_state(full)
            head = read_plan(full)[0]
            if st is None:
                m = next((STATUS_LINE.match(l) for l, f in zip(head, fenced(head)) if not f and STATUS_LINE.match(l)), None)
                if m and m[1] in LIVE:
                    rows.append({"plan": fn[:-3], "status": None, "ready": [], "nostate": True})
            elif st["status"] in LIVE:
                rows.append({**summary(full, st, head)})
        if as_json:
            print(json.dumps([{k: r.get(k) for k in ("plan", "status", "ready", "drift")} for r in rows], ensure_ascii=False))
        for r in rows:
            if not as_json:
                if r.get("nostate"):
                    print(f"{r['plan']} — no state — fix: run `pipeline.py approve` on it")
                else:
                    done = sum(p["status"] == "done" for p in r["phases"])
                    print(f"{r['plan']} — {r['status']} · {done}/{len(r['phases'])} phases done · ready: {', '.join(map(str, r['ready'])) or 'none'}"
                          + ("".join(f"\n  {x}" for x in r["drift"])))
        return 0
    md = plan_paths(plan)[0]
    st = load_state(plan)
    if st is None:
        raise Refuse("not-compiled", f"{plan} has no state file", f"run `pipeline.py approve {plan}`")
    head = read_plan(md)[0]
    s = summary(plan, st, head)
    if as_json:
        print(json.dumps(s, ensure_ascii=False))
        return 0
    print(f"{plan_slug(st)} — {st['title']}")
    print(f"Status: {st['status']} · branch `{st['branch']}` · base `{st['base']}`")
    t = tree_fact(plan, st)
    print(f"Tree: {t}" + ("" if os.path.isdir(t) else " (gone)"))
    if st.get("epic"):
        print(f"Epic: {st['epic']['path']} · row {st['epic']['row']}")
    if st.get("alloc"):
        print("Run: " + " · ".join(f"{k.replace('_', ' ')} {v}" for k, v in st["alloc"].items()))
    for c in st.get("cycles", []):
        if c["kind"] == "gate":
            print(f"Gate: {c['level']}" + (f" (raised by {', '.join(c['raised_by'])})" if c["raised_by"] else ""))
        if c["runs"]:
            print("\n".join(show_run(c["runs"][-1], True)).replace("checks at", "Checks at", 1).replace(" (reused, run", " (run", 1))
        lines = show_cycle(c)
        if lines:
            print(f"Cycle {cycle_label(c)}:")
        for l in lines:
            print(l)
    for l in show_judging(st):
        print(l)
    print("Phases:")
    for p in st["phases"]:
        print(f"  {p['n']}. {p['title']} — {p['status']}" + (f" (waits for {', '.join(map(str, p['waits']))})" if p["waits"] and p["status"] == "waiting" else ""))
        if p.get("grants"):
            print(f"     grants: {', '.join(p['grants'])}")
        if p.get("report"):
            print(f"     report: {p['report']['became']} (commits: {', '.join(c[:7] for c in p['report']['commits'])})")
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
    return 0


def cmd_plan(command, plan, value, note):
    with writing(plan) as st:
        if command == "status":
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


def branch_tree(root, branch):
    """The worktree where branch is checked out, or None."""
    here = None
    for l in git("worktree", "list", "--porcelain", check=False, cwd=root).stdout.splitlines():
        if l.startswith("worktree "):
            here = l[9:]
        elif l == f"branch refs/heads/{branch}":
            return here
    return None


def tree_fact(plan, st):
    """The tree the plan's branch lives in: where git has it checked out, else the recorded one, else the main checkout."""
    root = plan_root(plan_paths(plan)[0])
    return branch_tree(root, st["branch"]) or st.get("tree") or root


def tree_of(plan, st):
    t = tree_fact(plan, st)
    if not os.path.isdir(t):
        raise Refuse("tree-gone", f"the plan's tree {t} does not exist",
                     f"check the branch {st['branch']} out again, for example `git worktree add {t} {st['branch']}`")
    return t


def inside(path, roots):
    p = norm(path)
    return any(p == norm(t) or p.startswith(norm(t) + "/") for t in roots)


def owner_of(st, path, skip=None):
    """The running phase whose territory or grants hold path, or None."""
    return next((p for p in st["phases"] if p["status"] == "in progress" and p["n"] != skip
                 and any(overlaps(path, t) for t in p["territory"] + p.get("grants", []))), None)


def cmd_build_start(plan, base, worktree, branch, note):
    md = plan_paths(plan)[0]
    root = plan_root(md)
    with writing(plan) as st:
        if st["status"] != "approved":
            raise Refuse("not-approved", f"{plan_slug(st)} is {st['status']}, not approved",
                         "build start runs once on an approved plan; `pipeline.py plan status` moves a started one")
        r = git("rev-parse", "--verify", "-q", f"{base}^{{commit}}", check=False, cwd=root)
        if r.returncode:
            raise Refuse("unknown-ref", f"{base} is not a commit", "name a tag, branch or SHA with --base")
        sha, branch = r.stdout.strip(), branch or st["branch"]
        if git("rev-parse", "--verify", "-q", f"refs/heads/{branch}", check=False, cwd=root).returncode == 0:
            raise Refuse("branch-exists", f"branch {branch} already exists", "delete it, or name another with `build start --branch NAME`")
        iso = st.get("run", {}).get("isolation", {})
        if iso.get("worktree") and not worktree and not note:
            raise Refuse("worktree-required", "the run file asks for a worktree and --worktree was not given",
                         "pass --worktree PATH, or --note with the reason to build here")
        alloc = allocate(plan, md, st)
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
        st["tree"] = tree
        if alloc:
            st["alloc"] = alloc
            if "data_dir" in alloc:
                os.makedirs(alloc["data_dir"], exist_ok=True)
        set_plan(plan, st, status="building", base=sha, branch=branch, note=note)
        print(f"build start: {plan_slug(st)} building on {branch} at {sha[:7]}, tree {tree}")
        if alloc:
            print("facts: " + ", ".join(f"{k.replace('_', ' ')} {v}" for k, v in alloc.items()))
        for _, m, f in run_drift(plan, st):
            print(f"facts: {m} — fix: {f}")
        print(f"facts: was on {was}; tree was " + (f"dirty ({dirty} paths)" if dirty else "clean"))
    return 0


def cmd_phase_start(plan, n, note):
    with writing(plan) as st:
        ph = phase_of(st, n)
        if ph["status"] == "in progress":
            raise Refuse("running", f"phase {n} is already in progress", "report and finish it with `pipeline.py phase done`")
        if not note:
            if st["status"] == "approved":
                raise Refuse("not-building", f"{plan_slug(st)} is approved, with no branch yet",
                             "run `pipeline.py build start` first, or pass --note with the reason to start now")
            if ph["status"] == "done":
                raise Refuse("is-done", f"phase {n} is done", "pass --note with the reason to start it again")
            open_ = [x for x in ph["waits"] if phase_of(st, x)["status"] != "done"]
            if open_:
                raise Refuse("waits", f"phase {n} waits for {', '.join(map(str, open_))}, not done",
                             "finish them first, or pass --note with the reason to start now")
        set_phase(plan, st, n, "in progress", note)
        print(f"phase start: {n} {ph['title']} in progress")
    return 0


def cmd_phase_report(plan, n, a):
    with writing(plan) as st:
        ph = phase_of(st, n)
        if ph["status"] != "in progress":
            raise Refuse("not-running", f"phase {n} is {ph['status']}", f"`pipeline.py phase start {plan} {n}` first")
        ph["report"] = {"at": now(), "became": a.became, "skills": a.skills, "interfaces": a.interfaces,
                        "checks": a.checks, "commits": a.commit}
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
    return 0


def cmd_owner(plan, path):
    st = load_state(plan)
    if st is None:
        raise Refuse("not-compiled", f"{plan} has no state file", f"run `pipeline.py approve {plan}`")
    tree = tree_of(plan, st)
    rel = os.path.relpath(path, tree) if os.path.isabs(path) else path
    ph = owner_of(st, rel)
    print(f"phase {ph['n']} ({ph['title']}) owns {rel}" if ph else f"none: no running phase owns {rel}")
    for _, m, f in drift_diags(plan, st, read_plan(plan_paths(plan)[0])[0]):
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
        out += ["## Spec entries of the plan", ""]
        for e in entries:
            out.append(f"{e['sign']} {e['id']} — {e['statement'] or ''}".rstrip(" —"))
            if "Done" in e["keys"]:
                out += [f"  Done {x}: {done.get(x, '?')}" for x in cited(e, done, [])]
        out.append("")
    return out


def cmd_brief(plan, kind, n, note, cases=()):
    st = load_state(plan)
    if st is None:
        raise Refuse("not-compiled", f"{plan} has no state file", f"run `pipeline.py approve {plan}`")
    md = plan_paths(plan)[0]
    tree = tree_of(plan, st)
    drift = drift_diags(plan, st, read_plan(md)[0])
    if drift and kind == "implementer":
        r = Refuse(*drift[0])
        r.diags = drift
        raise r
    cli = f'python3 "{os.path.realpath(__file__)}"'
    head = git("rev-parse", "HEAD", check=False, cwd=tree).stdout.strip()
    out = [f"# Brief: {kind} — {st['title']}", "",
           f"Plan: {md}", f"Tree: {tree}", f"CLI: {cli}",
           f"Branch: {st['branch']}", f"Base: {st['base']}", f"HEAD: {head}",
           "Rules: " + (", ".join(x for x in (os.path.join(tree, "docs", "spec"), *(os.path.join(tree, f) for f in ("AGENTS.md", "CLAUDE.md"))) if os.path.exists(x)) or "none"), ""]
    if kind == "implementer":
        ph = phase_of(st, n)
        lines = read_plan(md)[0]
        mask = fenced(lines)
        i = next((k for k, l in enumerate(lines) if not mask[k] and (m := PHASE_HEAD.match(l)) and int(m[1]) == n), None)
        if i is None:
            raise Refuse("phase-text-gone", f"the plan file has no heading for phase {n}", f"run `pipeline.py approve {plan}` or restore the heading")
        j = next((k for k in range(i + 1, len(lines)) if lines[k].startswith("#") and not mask[k]), len(lines))
        sk = [os.path.join(tree, x) if os.path.exists(os.path.join(tree, x)) else x for x in ph["skills"]]
        sp = [os.path.join(tree, x) for x in ph["spec"]]
        out += [f"## Phase {n}, verbatim from the plan", "", *lines[i:j], "",
                f"Grants: {', '.join(ph.get('grants', [])) or 'none'}",
                f"Skills to read first: {', '.join(sk) or 'none'}", f"Spec area files: {', '.join(sp) or 'none'}", ""]
        if "run" in st:
            v = fill(st["run"], st.get("alloc"))
            out += ["## The run", "", "[checks].phase = " + json.dumps(v["checks"]["phase"], ensure_ascii=False), ""]
            out += [f"{k} = {json.dumps(x, ensure_ascii=False)}" for k, x in v["run"].items()]
            out += [f"Drift: {m} — fix: {f}" for _, m, f in run_drift(plan, st)] + [""]
        out += spec_entry_lines(md)
        for w in ph["waits"]:
            r = phase_of(st, w)
            out += [f"## Phase {w} reported ({r['title']})", ""]
            if r.get("report"):
                x = r["report"]
                out += [f"Became true: {x['became']}", f"Skills: {x['skills']}", f"Interfaces: {x['interfaces']}",
                        f"Checks: {x['checks']}", f"Commits: {', '.join(x['commits'])}", ""]
            else:
                out += ["no report recorded", ""]
        out += ["## Record", "",
                f"- Your report: {cli} phase report {md} {n} --became … --skills … --interfaces … --checks … --commit <sha> (repeat --commit)",
                f"- A ruling or product call: {cli} decision {md} --phase {n} --by implementer --question … --from … --answer … --why … --cost …",
                f"- A path outside the territory you need: ask the orchestrator; it runs `{cli} grant {md} {n} <path>`", ""]
        name = f"{plan_slug(st)}.brief-implementer-{n}.md"
    elif kind in ("reviewer", "verify", "fix"):
        body, name = brief_cycle(plan, st, kind, cli, md, tree, cases)
        out += body + [f"Drift: {m} — fix: {f}" for _, m, f in drift]
    elif kind == "round":
        body, name = brief_round(plan, st, cli, md, tree)
        out += body + [f"Drift: {m} — fix: {f}" for _, m, f in drift]
    else:
        body, name = brief_judge(plan, st, cli, md, note)
        out += body + [f"Drift: {m} — fix: {f}" for _, m, f in drift]
        last = (st.get("verdicts") or [{}])[-1]
        if last.get("kind") == "question" and note and last.get("answer") is None:
            with writing(plan) as w:
                w["verdicts"][-1]["answer"] = note
    out += ["## Orchestrator's note", "", note or "none", ""]
    path = os.path.join(os.path.dirname(md), name)
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
    g = lambda *a: git(*a, check=False, cwd=tree).stdout
    return hashlib.sha256((g("status", "--porcelain", "--untracked-files=all") + g("diff", "HEAD")).encode()).hexdigest()


def run_command(command, tree):
    """One full check on its own: its exit code, and red on a non-zero exit or a changed tree."""
    before = tree_snapshot(tree)
    r = subprocess.run(command, shell=True, cwd=tree, capture_output=True, text=True, errors="replace")
    changed = tree_snapshot(tree) != before
    out = {"command": command, "exit": r.returncode, "changed_tree": changed, "red": bool(r.returncode or changed)}
    if out["red"]:
        out["tail"] = "\n".join((r.stdout + r.stderr).rstrip().splitlines()[-20:])
    return out


def checks_of(st):
    if "run" not in st:
        raise Refuse("no-run-values", "the plan has no approved run values", "write the run file and run `pipeline.py approve`")
    return fill(st["run"], st.get("alloc"))["checks"]["full"]


def check_run(plan, st, cycle, tree):
    """Run `[checks].full` at HEAD unless the cycle already holds a run at this HEAD for these commands; -> (run, reused)."""
    cmds, head = checks_of(st), head_sha(plan_paths(plan)[0], tree)
    for r in cycle["runs"]:
        if r["head"] == head and r["full"] == cmds:
            return r, True
    run_ = {"at": now(), "head": head, "full": cmds, "commands": [run_command(c, tree) for c in cmds]}
    cycle["runs"].append(run_)
    return run_, False


def show_run(r, reused):
    green = not any(c["red"] for c in r["commands"])
    out = [f"checks at {r['head'][:7]}: " + ("green" if green else "red") + (f" (reused, run {r['at']})" if reused else f" (run {r['at']})")]
    for c in r["commands"]:
        why = ", changed the tree" if c["changed_tree"] else ""
        out.append(f"  {'red' if c['red'] else 'ok '}  {c['command']} — exit {c['exit']}{why}")
        out += [f"        {l}" for l in c.get("tail", "").splitlines()]
    return out


def commit_spec(plan, st, tree):
    """Write the rules with `spec write`, commit docs/spec/ alone; -> (lines for the report, the refusal's lines or None)."""
    md, buf = plan_paths(plan)[0], io.StringIO()
    here = os.getcwd()
    os.chdir(tree)
    try:
        with contextlib.redirect_stdout(buf):
            rc = run("write", md, None)
    finally:
        os.chdir(here)
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


def cmd_gate_start(plan, note):
    with writing(plan) as st:
        open_ = [p["n"] for p in st["phases"] if p["status"] != "done"]
        if open_ and not note:
            raise Refuse("phases-open", f"phase {', '.join(map(str, open_))} is not done", "finish them, or pass --note with the reason to open the gate now")
        tree = tree_of(plan, st)
        cycles = st.setdefault("cycles", [])
        cycle = next((c for c in cycles if c["kind"] == "gate"), None)
        if cycle is None:
            cycle = {"kind": "gate", "n": 1, "at": now(), "level": None, "raised_by": [], "spec_refusal": None,
                     "runs": [], "findings": [], "results": [], "fixes": []}
            cycles.append(cycle)
            record(plan, st, "gate", None, "opened", note)
        out, cycle["spec_refusal"] = commit_spec(plan, st, tree)
        cycle["level"], cycle["raised_by"] = level_of(st, tree)
        r, reused = check_run(plan, st, cycle, tree)
        print(f"gate: {plan_slug(st)} level {cycle['level']}" + (f", raised by {', '.join(cycle['raised_by'])}" if cycle["raised_by"] else ""))
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


def latest_results(c):
    last = {}
    for r in c["results"]:
        last[r["case"]] = r
    return last


def items(c):
    """The one list of a cycle, in this order: the rules' refusal, red checks, Defects, failed cases."""
    out = []
    if c.get("spec_refusal"):
        out.append({"id": "spec", "kind": "spec", "text": "spec write refused: " + "; ".join(c["spec_refusal"])})
    for i, x in enumerate(c["runs"][-1]["commands"] if c["runs"] else [], 1):
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
        do, _, see = text.partition(" → ")
        if a.outcome != "not-reached" and not a.capture:
            raise Refuse("no-capture", f"a {a.outcome} result has no capture", "pass --capture with the screenshot path or the command's output")
        if a.outcome != "passed" and not a.detail:
            raise Refuse("no-detail", f"a {a.outcome} result has no detail", "pass --detail: what was seen, or what is needed")
        c["results"].append({"at": now(), "case": a.case, "do": a.do or do, "see": a.see or see, "width": a.width or "-",
                             "outcome": a.outcome.replace("-", " "), "detail": a.detail, "capture": a.capture,
                             "commit": head_sha(plan_paths(plan)[0], tree_of(plan, st))})
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
            if c["fixes"] and not c["fixes"][-1]["done"]:
                raise Refuse("fix-open", f"fix {len(c['fixes'])} is running", "finish it with `fix report` and `fix done`")
            if len(c["fixes"]) >= FIXES_PER_CYCLE:
                raise Refuse("fixes-spent", f"this cycle's {len(c['fixes'])} fixes are spent", "what is open goes to the judge or the user")
            take = [i["id"] for i in items(c) if not taken(c, i["id"])]
            if not take:
                raise Refuse("nothing-open", "no open item for a fix", "an item a fix took stays with it")
            c["fixes"].append({"n": len(c["fixes"]) + 1, "at": now(), "from": head_sha(md, tree), "items": take, "report": None, "done": None, "survived": []})
            print(f"fix {len(c['fixes'])}: takes {', '.join(take)}")
            return 0
        f = open_fix(c)
        if a.command == "report":
            f["report"] = {"at": now(), "became": a.became, "skills": a.skills, "interfaces": a.interfaces, "checks": a.checks, "commits": a.commit}
            print(f"fix report: {f['n']} recorded, {len(a.commit)} commit(s)")
            return 0
        if not f["report"]:
            raise Refuse("no-report", f"fix {f['n']} has no report", "`pipeline.py fix report` first")
        gone = [x for x in f["report"]["commits"] if git("merge-base", "--is-ancestor", x, "HEAD", check=False, cwd=tree).returncode]
        if gone:
            raise Refuse("commit-gone", f"{', '.join(gone)} is not on the branch", "report the commits that are")
        out, c["spec_refusal"] = commit_spec(plan, st, tree)
        r, reused = check_run(plan, st, c, tree)
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


def show_cycle(c):
    out = []
    for kind, title in LISTS:
        fs = [f for f in c["findings"] if f["kind"] == kind]
        if fs:
            out.append(f"{title}:")
            out += [f"  {f['id']} " + (f"{f['where']} — " if f["where"] else "") + f["text"] + (f" ({f['source']})" if f["source"] else "")
                    + (f" [{f['again']} again]" if f["again"] else "") for f in fs]
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


def brief_cycle(plan, st, kind, cli, md, tree, cases):
    """The body and file name of a reviewer, verify or fix brief for the newest cycle."""
    c, label = cycle_of(st), None
    label = cycle_label(c)
    done = [f for f in c["fixes"] if f["done"]]
    last = done[-1] if done else None
    out, name = [], f"{plan_slug(st)}.brief-{kind}-{label}" + (f"-fix-{last['n']}" if last and kind != "fix" else "") + ".md"
    if kind == "reviewer":
        if last:
            made = (last["report"] or {}).get("commits", [])
            out += ([f"Range: {last['from']}..{last['done']['head']} (fix {last['n']}'s commits; a re-check reads only these)", "Commits: " + ", ".join(x[:7] for x in made)]
                    if made else [f"Range: none (fix {last['n']} made no commit)"])
            out += ["Items the fix took:"] + [f"- {i['id']} {i.get('where', '')} {i['text']}".replace("  ", " ") for i in items_of(c, last["items"])]
        elif c["kind"] == "round":
            out += [f"Range: {st['rounds'][c['n'] - 1]['from']}..HEAD (the round's commits)", f"Level: {c['level']}"]
        else:
            out += [f"Range: {st['base']}..HEAD", f"Level: {c['level']}"]
        if c["runs"]:
            out += [""] + show_run(c["runs"][-1], True)
        out += ["", "## Record", "", AS_PRINTED, "",
                f"- Each finding: {cli} finding {md} --kind defect|convention|observation --where <file:line> --source <rule or plan line> --text …",
                f"- What you could not judge: {cli} finding {md} --kind unjudged --text <what and why>"]
        if last:
            out += [f"- A Defect the fix took, found again: add --again <its ID>"]
        out += ["", "With no brief you return the three lists; with this one, record and return nothing longer.", ""]
    elif kind == "verify":
        failed = sorted(n for n, r in latest_results(c).items() if r["outcome"] == "failed")
        if last or c["kind"] == "round":
            want = sorted(set(failed) | set(cases))
        else:
            want = sorted(cases) or [d["n"] for d in st.get("done", []) if not d["you_check"]]
        out += ["## Cases to drive", ""]
        out += [f"{n}. {done_text(st, n)}" for n in want] or ["no case to drive"]
        out += ["", f"How to run the system: {cli} run show {md}", "", "Run each case's command exactly as written, one shell call per case.", "", "## Record", "", AS_PRINTED, "",
                f"- Each case: {cli} result {md} --case <n> --outcome passed|failed|not-reached --capture <path or output> [--detail <what was seen, or why not reached>] [--width <w>]", ""]
    else:
        f = c["fixes"][-1] if c["fixes"] else None
        if f is None or f["done"]:
            raise Refuse("no-fix", "no fix is running", "`pipeline.py fix start` first")
        sk = sorted({x for p in st["phases"] for x in p["skills"] if x != "none"})
        out += [f"## Fix {f['n']} takes", ""]
        for i in items_of(c, f["items"]):
            out.append(f"- {i['id']} " + (f"{i['where']} — " if i.get("where") else "") + i["text"] + (f" (capture: {i['capture']})" if i.get("capture") else ""))
            out += [f"    {l}" for l in i.get("tail", "").splitlines()]
        out += ["", "Skills to read first: " + (", ".join(os.path.join(tree, x) for x in sk) or "none"), ""] + spec_entry_lines(md) + ["## Record", "", AS_PRINTED, "",
                f"- Your report: {cli} fix report {md} --became … --skills … --interfaces … --checks … [--commit <sha>] (repeat --commit; none when the fix changed nothing)",
                f"- A ruling or product call: {cli} decision {md} --by implementer --question … --from … --answer … --why … --cost …", ""]
        name = f"{plan_slug(st)}.brief-fix-{label}-{f['n']}.md"
    return out, name


def items_of(c, ids):
    have = {i["id"]: i for i in items(c)}
    return [have.get(i, {"id": i, "text": "(no longer listed)"}) for i in ids]


# -- the verdict, the notes and the rounds

JUDGE_ROUNDS = 3
CAUSES = ["bug", "off-plan", "proto-mismatch", "grill-miss", "proto-miss", "feel-ui", "code-taste", "task"]
ACTIONS = ["let-through", "round", "question"]
SOURCE = re.compile(r"^(P\d+|missed)$")


def epoch(st):
    """How many rounds the user has started: each starts a new count of judge rounds."""
    return sum(r["by"] == "user" for r in st.get("rounds", []))


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
        out += ["", f"## Round {r['n']}{span}"] + [note_line(st, n) for n in st["notes"] if n["round"] == r["n"]]
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
            ns.append({"n": n, "text": a.text, "cause": a.cause, "by": "user", "source": None, "round": None, "verdict": None})
            print(f"note {n}: recorded")
        else:
            nt = next((x for x in ns if x["n"] == a.n), None)
            if nt is None:
                raise Refuse("no-note", f"there is no note {a.n}", "notes: " + ", ".join(str(x["n"]) for x in ns))
            if a.command == "edit" and a.source is not None:
                if nt["by"] != "user" or not SOURCE.match(a.source):
                    raise Refuse("bad-source", f"note {a.n} takes no source {a.source!r}", "a user's note is P<n>, a note the judge predicted, or missed; the judge's notes are marked by code")
                nt["source"] = a.source
            if (a.command == "drop" or a.text or a.cause) and (nt["round"] is not None or nt["by"] != "user"):
                raise Refuse("note-fixed", f"note {a.n} is a judge's note or already in a round", "only an open note of the user's changes")
            if a.command == "drop":
                ns.remove(nt)
            else:
                nt["text"], nt["cause"] = a.text or nt["text"], a.cause or nt["cause"]
            print(f"note {a.n}: {'dropped' if a.command == 'drop' else 'changed'}")
        write_notes(plan, st)
    return 0


def pending_round(st):
    """The last verdict when it ordered a round that has not started."""
    v = (st.get("verdicts") or [None])[-1]
    return v if v and v["kind"] == "round" and not v.get("stop") and v.get("round") is None else None


def cmd_round(plan, a):
    with writing(plan) as st:
        rs, md, tree = st.setdefault("rounds", []), plan_paths(plan)[0], tree_of(plan, st)
        if a.command == "start":
            if rs and not rs[-1]["done"]:
                raise Refuse("round-open", f"round {rs[-1]['n']} is running", "finish it with `round report` and `round done`")
            gate = next((c for c in st.get("cycles", []) if c["kind"] == "gate"), None)
            if gate is None:
                raise Refuse("no-cycle", "the gate was never opened", "run `pipeline.py gate start` first")
            v = pending_round(st)
            take = [n for n in st["notes"] if n["verdict"] == v["n"]] if v else open_notes(st)
            if not take:
                raise Refuse("nothing-open", "no open note for a round", "record the user's notes with `pipeline.py note add`")
            r = {"n": len(rs) + 1, "at": now(), "by": "judge" if v else "user", "from": head_sha(md, tree), "notes": [n["n"] for n in take], "report": None, "done": None}
            rs.append(r)
            st["cycles"].append({"kind": "round", "n": r["n"], "at": now(), "level": gate["level"], "raised_by": [], "spec_refusal": None,
                                 "runs": [], "findings": [], "results": [], "fixes": []})
            for n in take:
                n["round"] = r["n"]
            if v:
                v["round"] = r["n"]
            write_notes(plan, st)
            print(f"round {r['n']} ({r['by']}): takes notes {', '.join(map(str, r['notes']))}")
            return 0
        r = rs[-1] if rs and not rs[-1]["done"] else None
        if r is None:
            raise Refuse("no-round", "no round is running", "`pipeline.py round start` first")
        if a.command == "report":
            r["report"] = {"at": now(), "became": a.became, "skills": a.skills, "interfaces": a.interfaces, "checks": a.checks, "commits": a.commit}
            print(f"round report: {r['n']} recorded, {len(a.commit)} commit(s)")
            write_notes(plan, st)
            return 0
        if not r["report"]:
            raise Refuse("no-report", f"round {r['n']} has no report", "`pipeline.py round report` first")
        gone = [x for x in r["report"]["commits"] if git("merge-base", "--is-ancestor", x, "HEAD", check=False, cwd=tree).returncode]
        if gone:
            raise Refuse("commit-gone", f"{', '.join(gone)} is not on the branch", "report the commits that are")
        bare = [n["n"] for n in st["notes"] if n["round"] == r["n"] and n["source"] is None and n["by"] == "user"]
        if bare:
            raise Refuse("no-source", f"note {', '.join(map(str, bare))} has no source", "`pipeline.py note edit N --source P<n>|missed`")
        c = round_cycle(st, r["n"])
        out, c["spec_refusal"] = commit_spec(plan, st, tree)
        run_, reused = check_run(plan, st, c, tree)
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
    mine = [i for i, c in enumerate(st["cycles"]) if c["kind"] == "round" and st["rounds"][c["n"] - 1]["by"] == "user"]
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
    body = [v["report"]] + [f"Round: {t} — {c}" for t, c in a.note or []] + ([f"Question: {v['question']}"] if v["question"] else [])
    pred = [f"User's verdict: {a.predicted}"] + [f"P{i}. {t} — {c}" for i, (t, c) in enumerate(a.predict or [], 1)]
    return (f"# Judge: {plain_title(st)}\n\nPlan: `{plan_slug(st)}` · head `{v['head'][:7]}` · {v['at']} · engine {a.engine}\n\n"
            "## Verdict\n" + "\n".join(body) + "\n\n## Prediction\n" + "\n".join(pred) + "\n")


def cmd_verdict(plan, a):
    with writing(plan) as st:
        c, md = cycle_of(st), plan_paths(plan)[0]
        first = not st.get("verdicts")
        if first and not (a.predicted and a.engine):
            raise Refuse("no-prediction", "the first verdict records the Prediction and the engine", "pass --predicted pass|round, --predict TEXT CAUSE (repeat) and --engine claude|codex")
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
        miss = [i for i in need if i not in decided]
        if miss:
            raise Refuse("undecided", f"{', '.join(miss)} has no decision", "pass --decide ID ACTION REASON for each Open entry and Convention")
        stop = (stop_reason(st) or converging_stop(st, len(a.note or []))) if a.kind == "round" else None
        v = {"n": len(st.get("verdicts", [])) + 1, "at": now(), "head": head_sha(md, tree_of(plan, st)), "cycle": cycle_label(c), "kind": a.kind,
             "epoch": epoch(st), "report": a.report, "decisions": [{"id": i, "action": x, "reason": r} for i, x, r in a.decide or []],
             "notes": [], "stopped_notes": [], "question": a.question, "round": None, "stop": stop}
        ns = st.setdefault("notes", [])
        for text, cause in a.note or []:
            if stop:
                v["stopped_notes"].append([text, cause])
                continue
            ns.append({"n": 1 + max([x["n"] for x in ns], default=0), "text": text, "cause": cause, "by": "judge", "source": "judge", "round": None, "verdict": v["n"]})
            v["notes"].append(ns[-1]["n"])
        st.setdefault("verdicts", []).append(v)
        path = os.path.join(os.path.dirname(md), plan_slug(st) + ".judge.md")
        if first and not os.path.exists(path):
            text = render_judge(st, v, a)
            open(path, "w", encoding="utf-8").write(text)
        write_notes(plan, st)
        print(f"verdict {v['n']}: {a.kind} at {v['head'][:7]}" + (f"; round stopped: {stop}; no round opens, the judge lands as on a pass" if stop else ""))
    return 0


def show_judging(st):
    out = []
    for v in st.get("verdicts", []):
        out.append(f"Verdict {v['n']}: {v['kind']} at {v['head'][:7]} ({v['cycle']})")
        out += [f"  {d['id']} {d['action']} — {d['reason']}" for d in v["decisions"]]
        out += [f"  note {n}" for n in v["notes"]] + ([f"  question: {v['question']}"] if v["question"] else [])
        if v.get("stop"):
            out += [f"  Stopped: {v['stop']}"] + [f"  not taken: {t} — {c}" for t, c in v["stopped_notes"]]
    for r in st.get("rounds", []):
        out.append(f"Round {r['n']} ({r['by']}): takes notes {', '.join(map(str, r['notes']))}" + (f"; done at {r['done']['head'][:7]}" if r["done"] else "; running"))
        if r["report"]:
            out.append(f"  report: {r['report']['became']} (commits: {', '.join(x[:7] for x in r['report']['commits'])})")
    for title, ns in (("Open notes", open_notes(st)), ("Tasks", [n for n in st.get("notes", []) if n["cause"] == "task"])):
        if ns:
            out.append(f"{title}:")
            out += [f"  {n['n']}. {n['text']} — {n['cause']}" for n in ns]
    return out


def brief_judge(plan, st, cli, md, note):
    c = cycle_of(st)
    ref = os.path.join(os.path.dirname(os.path.realpath(__file__)), "references", "judge.md")
    if not os.path.isfile(ref):
        raise Refuse("no-judge-md", f"{ref} does not exist", "reinstall the plugin")
    slug, root = plan_slug(st), os.path.dirname(md)
    jf = os.path.join(root, slug + ".judge.md")
    asked = (st.get("verdicts") or [{}])[-1]
    asked = asked if asked.get("kind") == "question" else None
    answer = (asked or {}).get("answer") or note
    if asked and not answer:
        raise Refuse("no-answer", "the last verdict asked the user a question", "pass --note with the user's answer, in their words")
    out = [f"Judge rules: {ref}", f"Plan: {slug} — {st['title']}"]
    if st.get("epic"):
        out.append("Epic: " + os.path.join(plan_root(md), st["epic"]["path"]))
    if c["kind"] == "gate":
        left = [d["n"] for d in st.get("done", []) if not d["you_check"] and d["n"] not in latest_results(c)]
        if left and c["level"] != "small" and not note:
            raise Refuse("result-missing", f"Done {', '.join(map(str, left))} has no result at level {c['level']}", "record it, or pass --note with the reason to brief without it")
        out += ["Case: " + ("after the user's answer" if asked else "at the gate")] + ([f"Judge file: {jf}"] if asked else []) + [f"Level: {c['level']}" + (f" (raised by {', '.join(c['raised_by'])})" if c["raised_by"] else ""), ""]
        if c["runs"]:
            out += show_run(c["runs"][-1], True)
        if asked:
            out += [f"Question asked: {asked['question']}", f"The user's answer: {answer}", ""]
        out += show_cycle(c)
        out += ["Open:"] + [f"  {i['id']} " + (f"{i['where']} — " if i.get("where") else "") + i["text"] for i in items(c) if fate(c, i["id"]).startswith("open")]
        out += [f"Conventions: {', '.join(f['id'] for f in c['findings'] if f['kind'] == 'convention') or 'none'}",
                "You check: " + (", ".join(str(d["n"]) for d in st.get("done", []) if d["you_check"]) or "none")]
    else:
        if not os.path.exists(jf):
            raise Refuse("no-verdict", "no judge file exists yet", "the gate's `verdict` writes it")
        r = st["rounds"][c["n"] - 1]
        out += [f"Case: after round {r['n']} ({r['by']})", f"Judge file: {jf}", f"Notes file: {os.path.join(root, slug + '.notes.md')}", "", f"## Round {r['n']}'s notes", ""]
        out += [note_line(st, n) for n in st["notes"] if n["round"] == r["n"]] + [""]
        if asked:
            out += [f"Question asked: {asked['question']}", f"The user's answer: {answer}", ""]
        if c["runs"]:
            out += show_run(c["runs"][-1], True)
        out += show_cycle(c)
        out += ["Re-check verify: " + (e2e_text(st, r["n"]) or "no case to drive")]
    return out + [""], f"{slug}.brief-judge-{cycle_label(c)}.md"


def brief_round(plan, st, cli, md, tree):
    rs = st.get("rounds", [])
    if not rs or rs[-1]["done"]:
        raise Refuse("no-round", "no round is running", "`pipeline.py round start` first")
    r = rs[-1]
    sk = sorted({x for p in st["phases"] for x in p["skills"] if x != "none"})
    out = [f"## Round {r['n']} takes", "", f"Notes file: {os.path.join(os.path.dirname(md), plan_slug(st) + '.notes.md')}"]
    out += [f"- {n['n']}. {n['text']} — {n['cause']}" for n in st["notes"] if n["round"] == r["n"]]
    out += ["", "Skills to read first: " + (", ".join(os.path.join(tree, x) for x in sk) or "none"), ""] + spec_entry_lines(md) + ["## Record", "",
            f"- Your report: {cli} round report {md} --became … --skills … --interfaces … --checks … --commit <sha> (repeat --commit)",
            f"- A ruling or product call: {cli} decision {md} --by implementer --question … --from … --answer … --why … --cost …", ""]
    return out, f"{plan_slug(st)}.brief-round-{r['n']}.md"


def main():
    p = argparse.ArgumentParser(prog="pipeline.py")
    top = p.add_subparsers(dest="group", required=True)
    sp = top.add_parser("spec", prog="pipeline.py spec")
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
    s = top.add_parser("status", help="one plan's state, or the plans from building to passed")
    s.add_argument("--json", action="store_true", help="print as JSON")
    s.add_argument("plan", nargs="?", help="the plan file, any status; omit for the plans in .ai-workflow/plans/ from building to passed")
    pp = top.add_parser("plan", help="the plan's own status and base")
    psub = pp.add_subparsers(dest="command", required=True)
    for name, what in (("status", "set the plan's status; any value in the list, forward or back"),
                       ("base", "move the plan's base, for example after a rebase")):
        s = psub.add_parser(name, help=what)
        s.add_argument("--note", help="why")
        s.add_argument("plan", help="the plan file")
        s.add_argument("value", metavar="VALUE" if name == "status" else "REF",
                       help="draft, approved, building, at the human gate, passed, merged or a merge-request link" if name == "status" else "a tag, branch or SHA")
    bp = top.add_parser("build", help="the build as a whole")
    s = bp.add_subparsers(dest="command", required=True).add_parser(
        "start", help="cut the plan's branch at --base and set the plan to building")
    s.add_argument("--base", required=True, help="the ref the branch starts at (tag, branch or SHA); code never picks it")
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
    s.add_argument("--commit", action="append", required=True, help="a commit of this phase; repeat for each")
    s.add_argument("plan", help="the plan file")
    s.add_argument("n", type=int, help="the phase number")
    s = hsub.add_parser("done", help="check the report, its commits, their paths and the territory's tree, then mark the phase done")
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
    s = bsub.add_parser("judge", help="the judge's case, from the state: at the gate its checks, lists, results, fixes and Open; after a round the judge file, the round's notes and its re-check. At a level above small, refused while a case has no result unless --note")
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
    gp = top.add_parser("gate", help="the E2E gate")
    s = gp.add_subparsers(dest="command", required=True).add_parser(
        "start", help="write and commit the rules, compute the level, run the full checks unless this HEAD has a run")
    s.add_argument("--note", help="the reason to open the gate before every phase is done")
    s.add_argument("plan", help="the plan file")
    s = top.add_parser("finding", help="record a finding of the newest cycle: Defect, Convention, Observation, or what could not be judged")
    s.add_argument("--kind", required=True, choices=list(FINDING_KINDS))
    s.add_argument("--where", help="file:line; required except for unjudged")
    s.add_argument("--source", help="the rule or plan line it comes from")
    s.add_argument("--text", required=True, help="the finding")
    s.add_argument("--again", metavar="ID", help="a Defect a finished fix took, found again: it goes to Open")
    s.add_argument("plan", help="the plan file")
    s = top.add_parser("result", help="record a Done case's result; passed and failed need a capture")
    s.add_argument("--case", required=True, type=int, help="the Done item's number")
    s.add_argument("--outcome", required=True, choices=["passed", "failed", "not-reached"])
    s.add_argument("--capture", help="a capture path, or the command's output")
    s.add_argument("--detail", help="what was seen when failed, why when not reached")
    s.add_argument("--width", help="the width driven")
    s.add_argument("--do", help="default: the Done item's text before the arrow")
    s.add_argument("--see", help="default: the Done item's text after the arrow")
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
    s.add_argument("plan", help="the plan file")
    s = top.add_parser("verdict", help="the judge's verdict on the newest cycle: a decision for every Open entry and Convention, each --decide action one of let-through, round or question; the first one writes .judge.md and alone takes --predicted, --predict and --engine. A round verdict past the cap, or on an early-stop sign, records the stop and opens no round")
    s.add_argument("kind", choices=["pass", "round", "question"])
    s.add_argument("--report", required=True, help="what was let through and why, in the judge's words")
    s.add_argument("--decide", nargs=3, action="append", metavar=("ID", "ACTION", "REASON"), help="let-through, round or question for an Open entry or a Convention; repeat for each")
    s.add_argument("--note", nargs=2, action="append", metavar=("TEXT", "CAUSE"), help="a round verdict's note in the judge's words, with its cause; repeat for each")
    s.add_argument("--question", help="the question for the user, for a question verdict or beside round notes")
    s.add_argument("--predicted", choices=["pass", "round"], help="the user's verdict as predicted; the first verdict only")
    s.add_argument("--predict", nargs=2, action="append", metavar=("TEXT", "CAUSE"), help="a note the user will make, with its cause; the first verdict only, repeat for each")
    s.add_argument("--engine", choices=["claude", "codex"], help="the engine the judge runs on; the first verdict only")
    s.add_argument("plan", help="the plan file")
    np_ = top.add_parser("note", help="the user's notes, in their words; code numbers them and renders the notes file")
    nsub = np_.add_subparsers(dest="command", required=True)
    s = nsub.add_parser("add", help="record a note: its words and its cause (task is a verdict: listed, never built)")
    s.add_argument("--text", required=True, help="the note in the user's words")
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
    s = rosub.add_parser("start", help="take the judge's notes when the last verdict ordered a round, else every open note; the user's round starts a new count")
    s.add_argument("plan", help="the plan file")
    s = rosub.add_parser("report", help="record the round's report; a second call replaces the first")
    s.add_argument("--became", required=True, help="what became true")
    s.add_argument("--skills", default="none", help="the skills read")
    s.add_argument("--interfaces", default="none", help="interfaces changed")
    s.add_argument("--checks", default="none", help="the checks run and their result")
    s.add_argument("--commit", action="append", required=True, help="a commit of this round; repeat for each")
    s.add_argument("plan", help="the plan file")
    s = rosub.add_parser("done", help="refused while a note of the user's has no source; writes and commits the rules, runs the full checks at the new HEAD, completes the notes file")
    s.add_argument("plan", help="the plan file")
    rp = top.add_parser("run", help="the run file beside the plan: its path need not exist yet")
    rsub = rp.add_subparsers(dest="command", required=True)
    s = rsub.add_parser("new", help="copy the newest run file in the plan's directory, else the shipped example; refused if the file exists")
    s.add_argument("plan", help="the plan file, which need not exist")
    s = rsub.add_parser("check", help="print every problem of the run file, silent when it is sound")
    s.add_argument("plan", help="the plan file, which need not exist")
    s = rsub.add_parser("show", help="the run file's values: the approved ones once the plan is approved, with any drift")
    s.add_argument("--json", action="store_true", help="print as JSON: run, approved, drift")
    s.add_argument("plan", help="the plan file, which need not exist")
    a = p.parse_args()
    try:
        if a.group == "run":
            return cmd_run(a.command, a.plan, getattr(a, "json", False))
        if a.group == "approve":
            return cmd_approve(a.plan, a.json)
        if a.group == "status":
            return cmd_status(a.plan, a.json, os.getcwd())
        if a.group == "plan":
            return cmd_plan(a.command, a.plan, a.value, a.note)
        if a.group == "build":
            return cmd_build_start(a.plan, a.base, a.worktree, a.branch, a.note)
        if a.group == "phase":
            return {"start": lambda: cmd_phase_start(a.plan, a.n, a.note), "report": lambda: cmd_phase_report(a.plan, a.n, a),
                    "done": lambda: cmd_phase_done(a.plan, a.n, a.note)}[a.command]()
        if a.group == "owner":
            return cmd_owner(a.plan, a.path)
        if a.group == "grant":
            return cmd_grant(a.plan, a.n, a.path, a.note)
        if a.group == "gate":
            return cmd_gate_start(a.plan, a.note)
        if a.group == "finding":
            return cmd_finding(a.plan, a)
        if a.group == "result":
            return cmd_result(a.plan, a)
        if a.group == "fix":
            return cmd_fix(a.plan, a)
        if a.group == "verdict":
            return cmd_verdict(a.plan, a)
        if a.group == "note":
            return cmd_note(a.plan, a)
        if a.group == "round":
            return cmd_round(a.plan, a)
        if a.group == "decision":
            return cmd_decision(a.plan, a)
        if a.group == "brief":
            return cmd_brief(a.plan, a.command, getattr(a, "n", None), a.note, [int(x) for x in getattr(a, "cases", "").split(",") if x.strip()])
    except Refuse as e:
        for code, message, fix in e.diags:
            print(f"{code}: {message} — fix: {fix}")
        return 1
    if a.command in ("list", "show"):
        return read_spec(a.command, getattr(a, "id", None))
    return run(a.command, a.plan, a.base)


if __name__ == "__main__":
    sys.exit(main())
