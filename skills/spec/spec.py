#!/usr/bin/env python3
"""Keep a project's rules in docs/spec/, written from plans.

Usage: spec.py check [--base REV] PLAN
       spec.py write [--base REV] PLAN
       spec.py list
       spec.py show ID

check reads the plan's `## Spec` section against docs/spec/ as it is at the
base (--base, else the base in the plan's Status line, else HEAD) and reports
every problem as `<file>:<line>: <message>`, exit 1; that includes what write
would drop or alter in a base area file (`docs/spec/<area>.md:<line>`) and an
archive record of the plan's file name already at the base, and a plan without
a `# ` title. write runs check, refuses when the working tree's docs/spec/ is
not the base plus what this plan's earlier archive record (its Done and Spec)
produces, makes docs/spec/ equal to the base plus the section, and
writes the archive record. A bad argument is exit 2.

list prints every area (`<area> — <title>`) and under it its rules, indented
(`  <area>#<rule> — <statement>`), from the working tree. show prints the rule
`<area>#<rule>` (heading, Why, scenarios), then each archive record whose Spec
section names it, newest file name first: `## archive/<file> — <plan title>`
and that section's entry for the rule. An ID that is not a rule is
`spec.py: no rule <id>` on stderr, exit 1.
"""

import argparse
import os
import re
import subprocess
import sys

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


def git(*args, check=True):
    r = subprocess.run(["git", *args], capture_output=True, text=True)
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
        elif line.startswith("- "):
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
        out += [f"### {r['id']} — {r['statement']}", f"Why: {r['why']}"]
        out += [f"- {s}" for s in r["scenarios"]]
        out.append("")
    return "\n".join(out).rstrip("\n") + "\n"


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


def done_items(body):
    items, last = {}, None
    for line in body:
        m = re.match(r"^(\d+)\.\s+(.*)$", line)
        if m:
            last = int(m[1])
            items[last] = m[2]
        elif last and line.startswith((" ", "\t")) and line.strip():
            items[last] += " " + line.strip()
    return {n: re.sub(r"\s*—\s*you check\.?\s*$", "", t).strip() for n, t in items.items()}


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
    for name in ("Result", "Approach", "Out of scope", "Done", "Spec"):
        if name in secs:
            out += [f"## {name}", *secs[name][1]]
            while out and not out[-1].strip():
                out.pop()
            out.append("")
    return "\n".join(out).rstrip("\n") + "\n"


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
        print("spec.py: not inside a git repository", file=sys.stderr)
        return 1
    try:
        with open(plan, encoding="utf-8") as f:
            plan_lines = f.read().splitlines()
    except OSError as e:
        print(f"spec.py: {e}", file=sys.stderr)
        return 2
    name = os.path.basename(plan)
    try:
        tree = tree_at(base_of(plan_lines, given_base))
    except Fail as e:
        print(f"{plan}:1: {e}")
        return 1
    base_problems = []
    base = areas_of(tree, base_problems)
    spec, problems = apply(plan_lines, base)
    out = []
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
        rsecs = sections(record.splitlines())
        # a record without Done is an old format: the plan's own Done stands in
        done = (rsecs.get("Done") or sections(plan_lines).get("Done", (0, [])))[1]
        old, probs = apply(["## Done", *done, "## Spec", *rsecs.get("Spec", (0, []))[1]], base)
        if old is not None and not probs:
            expected = {**render_tree(tree, old), "archive/" + name: record}
    differ = sorted(p for p in work.keys() | expected.keys() if work.get(p) != expected.get(p))
    if differ:
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
        print("spec.py: not inside a git repository", file=sys.stderr)
        return 1
    spec = spec_on_disk(root)
    if command == "list":
        for name, area in spec.items():
            print(f"{name} — {area['title']}")
            for r in area["rules"]:
                print(f"  {name}#{r['id']} — {r['statement']}")
        return 0
    name, _, rid = rule_id.partition("#")
    rule = next((r for r in spec.get(name, {"rules": []})["rules"] if r["id"] == rid), None)
    if rule is None:
        print(f"spec.py: no rule {rule_id}", file=sys.stderr)
        return 1
    print(f"{rule_id} — {rule['statement']}")
    print(f"Why: {rule['why']}")
    for sc in rule["scenarios"]:
        print(f"- {sc}")
    adir = os.path.join(root, "docs", "spec", "archive")
    for fn in sorted(os.listdir(adir), reverse=True) if os.path.isdir(adir) else []:
        lines = open(os.path.join(adir, fn), encoding="utf-8").read().splitlines()
        body = sections(lines).get("Spec", (0, []))[1]
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


def main():
    p = argparse.ArgumentParser(prog="spec.py")
    sub = p.add_subparsers(dest="command", required=True)
    for name in ("check", "write"):
        s = sub.add_parser(name)
        s.add_argument("--base")
        s.add_argument("plan")
    sub.add_parser("list")
    sub.add_parser("show").add_argument("id")
    a = p.parse_args()
    if a.command in ("list", "show"):
        return read_spec(a.command, getattr(a, "id", None))
    return run(a.command, a.plan, a.base)


if __name__ == "__main__":
    sys.exit(main())
