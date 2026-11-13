#!/usr/bin/env bash
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"
spec="$repo_root/skills/spec/spec.py"

. "$repo_root/test/lib/harness.sh"

fail() {
  echo "spec.test.sh: $1" >&2
  exit 1
}

repo=$(mktemp_dir)
cd "$repo" || exit 1
git init -q
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git commit -q --allow-empty -m base
mkdir -p .ai-workflow/plans

plan1=.ai-workflow/plans/2026-11-13-card-editor.md
cat > "$plan1" <<'P'
# Plan: card editor

Status: building · branch `x` · base `HEAD`

## Result

Cards can be edited.

## Approach

A form.

## Out of scope

- Drafts.

## Done

1. Change a card, press "Save" → the editor is closed. — you check
2. Edit a card in two tabs → the later save wins.
3. Open the log → it shows "All time".

## Spec

+ card-editor — Card editor
  About: The form where a card's text and fields are edited.
+ card-editor#save-closes — Saving closes the editor
  Why: the result shows in the list; the editor is a visit — not a place to stay.
  Done: 1
+ card-editor#keeps-draft — A draft is kept
  Why: no work is lost
  Done: 2, 3
P

# 1: write on the epic's shape
python3 "$spec" write "$plan1"
assert_exit 0 "TC-1: write exits 0" || fail "TC-1"
area=$(cat docs/spec/card-editor.md)
assert_eq '# Card editor

The form where a card'"'"'s text and fields are edited.

### save-closes — Saving closes the editor
Why: the result shows in the list; the editor is a visit — not a place to stay.
- Change a card, press "Save" → the editor is closed.

### keeps-draft — A draft is kept
Why: no work is lost
- Edit a card in two tabs → the later save wins.
- Open the log → it shows "All time".' "$area" "TC-1: the area file" || fail "TC-1 area"
arch=$(cat docs/spec/archive/2026-11-13-card-editor.md)
assert_contains "$arch" "This is history; the rules that hold now are in \`docs/spec/\`." "TC-1: history line" || fail "TC-1"
assert_eq "This is history; the rules that hold now are in \`docs/spec/\`." "$(head -1 docs/spec/archive/2026-11-13-card-editor.md)" "TC-1: first line" || fail "TC-1 first"
for h in "# Plan: card editor" "## Result" "## Approach" "## Out of scope" "## Spec" "+ card-editor#keeps-draft"; do
  assert_contains "$arch" "$h" "TC-1: archive holds $h" || fail "TC-1 $h"
done
case "$arch" in *"Status:"*) fail "TC-1: archive copies only the named sections";; esac
assert_contains "$arch" '## Done

1. Change a card, press "Save" → the editor is closed. — you check
2. Edit a card in two tabs → the later save wins.
3. Open the log → it shows "All time".

## Spec' "TC-1: the Done section sits before Spec, as it is" || fail "TC-1 done"
[ -f docs/spec/README.md ] || fail "TC-1: README.md written"

# 2: change one rule, remove the other
git add -A && git commit -q -m one
plan2=.ai-workflow/plans/2026-11-14-save.md
cat > "$plan2" <<'P'
# Plan: save

Status: building · branch `x` · base `HEAD`

## Done

1. Press "Save" → closed.
5. Autosave runs → the editor stays open.

## Spec

~ card-editor#save-closes — An explicit "Save" closes the editor, autosave does not
  Why: a visit, not a place to stay
  Done: 5
- card-editor#keeps-draft
  Why: no draft once the editor closes
P
python3 "$spec" write "$plan2"
assert_exit 0 "TC-2: write exits 0" || fail "TC-2"
area=$(cat docs/spec/card-editor.md)
assert_contains "$area" '### save-closes — An explicit "Save" closes the editor, autosave does not' "TC-2: new statement" || fail "TC-2"
assert_contains "$area" "Why: a visit, not a place to stay" "TC-2: new reason" || fail "TC-2"
assert_contains "$area" "- Autosave runs → the editor stays open." "TC-2: new scenario" || fail "TC-2"
case "$area" in *keeps-draft*|*"Press"*) fail "TC-2: removed rule or old scenario remains";; esac
[ "$(ls docs/spec/archive | wc -l)" -eq 2 ] || fail "TC-2: two archive records"

# 5: list and show
out=$(python3 "$spec" list)
assert_eq 'card-editor — Card editor
  card-editor#save-closes — An explicit "Save" closes the editor, autosave does not' "$out" "TC-5: list" || fail "TC-5 list: $out"
out=$(python3 "$spec" show card-editor#save-closes)
assert_exit 0 "TC-5: show exits 0" || fail "TC-5"
assert_eq 'card-editor#save-closes — An explicit "Save" closes the editor, autosave does not
Why: a visit, not a place to stay
- Autosave runs → the editor stays open.

## archive/2026-11-14-save.md — Plan: save
~ card-editor#save-closes — An explicit "Save" closes the editor, autosave does not
  Why: a visit, not a place to stay
  Done: 5

## archive/2026-11-13-card-editor.md — Plan: card editor
+ card-editor#save-closes — Saving closes the editor
  Why: the result shows in the list; the editor is a visit — not a place to stay.
  Done: 1' "$out" "TC-5: show" || fail "TC-5 show: $out"
err=$(python3 "$spec" show card-editor#nope 2>&1 >/dev/null)
assert_exit 1 "TC-5: unknown rule exits 1" || fail "TC-5 unknown"
assert_eq "spec.py: no rule card-editor#nope" "$err" "TC-5: unknown message" || fail "TC-5 msg"
python3 "$spec" show card-editor >/dev/null 2>&1; assert_exit 1 "TC-5: an area is not a rule" || fail "TC-5 area"
python3 "$spec" show >/dev/null 2>&1; assert_exit 2 "TC-5: show needs an ID" || fail "TC-5 arg"

# 3: edit the section, write again, straight after TC-2's write: no reset, so a merge onto the working tree would show
cat >> "$plan2" <<'P'
+ card-editor#extra — Extra
  Why: because
  Done: 1
P
python3 "$spec" write "$plan2"
assert_exit 0 "TC-3: second write exits 0" || fail "TC-3"
area=$(cat docs/spec/card-editor.md)
assert_eq 1 "$(grep -c '^### save-closes' <<<"$area")" "TC-3: nothing doubled" || fail "TC-3"
assert_contains "$area" "### extra — Extra" "TC-3: the new rule" || fail "TC-3"
[ "$(ls docs/spec/archive | wc -l)" -eq 2 ] || fail "TC-3: still two records"

# 2b: ~ without Done keeps the scenarios
git checkout -q -- docs; git clean -fdq docs
plan3=.ai-workflow/plans/2026-11-15-reason.md
cat > "$plan3" <<'P'
# Plan: reason

## Done

1. x

## Spec

~ card-editor#save-closes — An explicit "Save" closes the editor
  Why: corrected reason
P
python3 "$spec" write "$plan3" || fail "TC-2b: write"
area=$(cat docs/spec/card-editor.md)
assert_contains "$area" "Why: corrected reason" "TC-2b" || fail "TC-2b"
assert_contains "$area" "- Change a card, press" "TC-2b: scenarios stay" || fail "TC-2b scenarios"
git checkout -q -- docs; git clean -fdq docs

# 4: problems, all at once, nothing written
bad=.ai-workflow/plans/bad.md
cat > "$bad" <<'P'
# Plan: bad

## Done

1. a
2. b
3. c

## Spec

~ card-editor#nope — x
  Why: y
+ card-editor#save-closes — dup
  Why: y
  Done: 1
+ ghost#r — x
  Why: y
  Done: 9
+ card-editor#late — x
  Why: y
P
out=$(python3 "$spec" check "$bad")
assert_exit 1 "TC-4: check exits 1" || fail "TC-4"
for m in "$bad:11: rule card-editor#nope does not exist" "$bad:13: rule card-editor#save-closes already exists" \
  "$bad:16: area ghost does not exist" "$bad:19: card-editor#late: an added rule needs a Done: line"; do
  assert_contains "$out" "$m" "TC-4: $m" || fail "TC-4: $out"
done
sed -i.bak 's/Done: 1$/Done: 9/' "$bad"; rm -f "$bad.bak"
out=$(python3 "$spec" check "$bad")
assert_contains "$out" "cites item 9, the plan has 3" "TC-4: missing Done item" || fail "TC-4: $out"
python3 "$spec" write "$bad" >/dev/null
assert_exit 1 "TC-4: write fails too" || fail "TC-4 write"
[ -z "$(git status --porcelain docs)" ] || fail "TC-4: write wrote on a failed check"

printf '# P\n\n## Result\n\nr\n' > .ai-workflow/plans/nospec.md
out=$(python3 "$spec" check .ai-workflow/plans/nospec.md)
assert_exit 1 "TC-4: no Spec section" || fail "TC-4 nospec"
assert_contains "$out" "nospec.md:1: no \`## Spec\` section" "TC-4: missing section message" || fail "TC-4 nospec"

none=.ai-workflow/plans/none.md
printf '# P\n\n## Spec\n\nnone\n' > "$none"
python3 "$spec" check "$none"; assert_exit 0 "TC-4: none passes" || fail "TC-4 none"
python3 "$spec" write "$none"; assert_exit 0 "TC-4: none writes" || fail "TC-4 none write"
[ -z "$(git status --porcelain docs)" ] || fail "TC-4: none wrote something"

# 1: from a subdirectory the base is the repo's, not the directory's
git add -A && git commit -q -m two
mkdir -p sub
logplan=.ai-workflow/plans/log.md
printf '# L\n\n## Done\n\n1. x\n\n## Spec\n\n+ log — Log\n  About: the log\n+ log#r — R\n  Why: y\n  Done: 1\n' > "$logplan"
(cd sub && python3 "$spec" write "../$logplan") || fail "TC-1b: write from a subdirectory"
[ -f docs/spec/card-editor.md ] || fail "TC-1b: write from a subdirectory deleted an area file"
[ -f docs/spec/log.md ] || fail "TC-1b: log area written"
git checkout -q -- docs; git clean -fdq docs
out=$(cd sub && python3 "$spec" check "../$bad")
case "$out" in *"save-closes already exists"*) ;; *) fail "TC-1b: check from a subdirectory sees the base: $out";; esac

# the base named in the Status line, not HEAD
older=$(git rev-parse HEAD~2)
baseplan=.ai-workflow/plans/older.md
printf '# B\n\nStatus: building · base `%s`\n\n## Done\n\n1. x\n\n## Spec\n\n+ card-editor — Card editor\n  About: the form\n' "$older" > "$baseplan"
python3 "$spec" check "$baseplan"; assert_exit 0 "TC-6: the older base has no card-editor" || fail "TC-6"
sed -i.bak 's/base `[^`]*`/base `HEAD`/' "$baseplan"; rm -f "$baseplan.bak"
python3 "$spec" check "$baseplan" >/dev/null; assert_exit 1 "TC-6: HEAD has card-editor" || fail "TC-6 head"

# an empty Spec, an empty Why, fenced headings, a second Spec
e1=.ai-workflow/plans/empty.md
printf '# P\n\n## Spec\n\n## Result\n\nr\n' > "$e1"
out=$(python3 "$spec" check "$e1"); assert_exit 1 "TC-7: empty Spec" || fail "TC-7"
assert_contains "$out" "empty.md:3: the \`## Spec\` section is empty; write \`none\` when no rule changes" "TC-7: message" || fail "TC-7: $out"
e2=.ai-workflow/plans/emptywhy.md
printf '# P\n\n## Done\n\n1. x\n\n## Spec\n\n~ card-editor#save-closes — S\n  Why:\n' > "$e2"
out=$(python3 "$spec" check "$e2"); assert_exit 1 "TC-8: empty Why" || fail "TC-8"
assert_contains "$out" "emptywhy.md:9: card-editor#save-closes: Why: is empty" "TC-8: message" || fail "TC-8: $out"
e3=.ai-workflow/plans/fenced.md
cat > "$e3" <<'P'
# P

## Approach

```markdown
## Spec

none
```

after

## Spec

+ log — Log
  About: the log
P
python3 "$spec" write "$e3"; assert_exit 0 "TC-9: fenced Spec is not a heading" || fail "TC-9"
rec=$(cat docs/spec/archive/fenced.md)
assert_contains "$rec" "after" "TC-9: Approach keeps its tail" || fail "TC-9 tail"
assert_contains "$rec" "+ log — Log" "TC-9: the real Spec is archived" || fail "TC-9 spec"
[ -f docs/spec/log.md ] || fail "TC-9: the real Spec applied"
git checkout -q -- docs; git clean -fdq docs
e4=.ai-workflow/plans/twice.md
printf '# P\n\n## Spec\n\n+ log — Log\n  About: the log\n\n## Spec\n\nnone\n' > "$e4"
out=$(python3 "$spec" check "$e4"); assert_exit 1 "TC-9: a second Spec" || fail "TC-9b"
assert_contains "$out" "twice.md:8: a second \`## Spec\` section" "TC-9: message" || fail "TC-9b: $out"


# 10: two writes with no commit between; the same plan again, also when its first write is committed
two=$(mktemp_dir); cd "$two" || exit 1
git init -q; git commit -q --allow-empty -m base; mkdir p q
base0=$(git rev-parse HEAD)
mkplan() { printf '# T\n\nStatus: building · base `%s`\n\n## Done\n\n1. x → y\n\n## Spec\n\n+ %s — %s\n  About: a\n+ %s#r — R\n  Why: w\n  Done: 1\n' "$base0" "$2" "$2" "$2" > "$1"; }
mkplan p/2026-11-20-a.md alpha; mkplan p/2026-11-21-b.md beta
python3 "$spec" write p/2026-11-20-a.md || fail "TC-10: write A"
before=$(git status --porcelain -uall)
out=$(python3 "$spec" write p/2026-11-21-b.md)
assert_exit 1 "TC-10: write B over A's uncommitted write" || fail "TC-10: $out"
assert_contains "$out" "docs/spec/alpha.md" "TC-10: names the path" || fail "TC-10 path: $out"
assert_eq "$before" "$(git status --porcelain -uall)" "TC-10: nothing written" || fail "TC-10 written"
python3 "$spec" write p/2026-11-20-a.md || fail "TC-10: A again replaces its write"
git add -A && git commit -q -m a
printf '+ alpha#s — S\n  Why: w\n  Done: 1\n' >> p/2026-11-20-a.md
python3 "$spec" write p/2026-11-20-a.md || fail "TC-10: A again after its write is committed"
assert_contains "$(cat docs/spec/alpha.md)" "### s — S" "TC-10: the new rule" || fail "TC-10 rule"
assert_eq 1 "$(grep -c '^### r ' docs/spec/alpha.md)" "TC-10: nothing doubled" || fail "TC-10 doubled"
echo "a hand edit" >> docs/spec/alpha.md
out=$(python3 "$spec" write p/2026-11-20-a.md)
assert_exit 1 "TC-10: a hand edit is not explained" || fail "TC-10 edit"
assert_contains "$out" "docs/spec/alpha.md" "TC-10: names the edited file" || fail "TC-10 edit: $out"

# 10b: same file name, different plans, no commit between: the second write refuses and says what to do
nm=$(mktemp_dir); cd "$nm" || exit 1
git init -q; git commit -q --allow-empty -m base; mkdir p q
mkt() { printf '# %s\n\n## Done\n\n1. x → y\n\n## Spec\n\n+ %s — %s\n  About: a\n+ %s#r — R\n  Why: w\n  Done: 1\n' "$2" "$2" "$2" "$2" > "$1"; }
mkt p/n.md alpha; mkt q/n.md beta
python3 "$spec" write p/n.md || fail "TC-10b: write p"
before=$(git status --porcelain -uall); rec=$(cat docs/spec/archive/n.md)
out=$(python3 "$spec" write q/n.md)
assert_exit 1 "TC-10b: second write refuses" || fail "TC-10b: $out"
assert_contains "$out" "another plan's uncommitted write or a hand edit; commit or discard it first" "TC-10b: the cause and the next step" || fail "TC-10b: $out"
assert_eq "$before" "$(git status --porcelain -uall)" "TC-10b: nothing written" || fail "TC-10b written"
assert_eq "$rec" "$(cat docs/spec/archive/n.md)" "TC-10b: the first record kept" || fail "TC-10b record"
[ -f docs/spec/alpha.md ] || fail "TC-10b: alpha.md kept"
# the same plan again with a cited Done item reworded: its write is replaced
sed -i.bak 's/x → y/z → w/' p/n.md; rm p/n.md.bak
python3 "$spec" write p/n.md || fail "TC-10b: a reworded Done item replaces the write"
assert_contains "$(cat docs/spec/alpha.md)" "z → w" "TC-10b: the new text" || fail "TC-10b new text"
echo "a hand edit" >> docs/spec/alpha.md
out=$(python3 "$spec" write p/n.md)
assert_exit 1 "TC-10b: a hand edit on top of the write refuses" || fail "TC-10b edit: $out"
assert_contains "$out" "docs/spec/alpha.md differs from the base, and it is not what this plan's earlier write left (a hand edit, or the base moved); commit or discard it first" "TC-10b: message" || fail "TC-10b edit: $out"

# 11: an archive record with the plan's file name is already at the base
one=$(mktemp_dir); cd "$one" || exit 1
git init -q; git commit -q --allow-empty -m base; mkdir p q
mkplan() { printf '# T\n\n## Done\n\n1. x → y\n\n## Spec\n\n+ %s — %s\n  About: a\n+ %s#r — R\n  Why: w\n  Done: 1\n' "$2" "$2" "$2" > "$1"; }
mkplan p/2026-11-14-one.md alpha; mkplan q/2026-11-14-one.md beta
python3 "$spec" write p/2026-11-14-one.md || fail "TC-11: write p"
git add -A && git commit -q -m p
out=$(python3 "$spec" check q/2026-11-14-one.md)
assert_exit 1 "TC-11: check refuses" || fail "TC-11"
assert_contains "$out" "q/2026-11-14-one.md:1: the archive record 2026-11-14-one.md already exists at the base" "TC-11: message" || fail "TC-11: $out"
python3 "$spec" write q/2026-11-14-one.md >/dev/null; assert_exit 1 "TC-11: write refuses" || fail "TC-11 write"
[ -z "$(git status --porcelain docs)" ] || fail "TC-11: the committed record is untouched"

# 12: what write would drop or alter in a base area file is a problem; a file write made is not
mkplan q/2026-11-15-two.md gamma
python3 "$spec" check q/2026-11-15-two.md; assert_exit 0 "TC-12: a file written by write is clean" || fail "TC-12 roundtrip"
cat > docs/spec/alpha.md <<'P'
# Alpha

About text.

### r — R
Why: because
- Change → closed.

A paragraph the script does not know.

### no-why — A rule without a reason
- Scenario.

### empty-why — A rule with an empty reason
Why:
- Scenario.
P
git add -A && git commit -q -m hand
out=$(python3 "$spec" check q/2026-11-15-two.md)
assert_exit 1 "TC-12: check exits 1" || fail "TC-12"
assert_contains "$out" "docs/spec/alpha.md:9: " "TC-12: the paragraph" || fail "TC-12 paragraph: $out"
assert_contains "$out" "docs/spec/alpha.md:11: rule no-why: no Why: line" "TC-12: no Why" || fail "TC-12 no why: $out"
assert_contains "$out" "docs/spec/alpha.md:14: rule empty-why: Why: is empty" "TC-12: empty Why" || fail "TC-12 empty why: $out"
python3 "$spec" write q/2026-11-15-two.md >/dev/null; assert_exit 1 "TC-12: write refuses" || fail "TC-12 write"
[ -z "$(git status --porcelain -uall docs)" ] || fail "TC-12: write wrote"

# 13: About: is required on a new area
ab=$(mktemp_dir); cd "$ab" || exit 1
git init -q; git commit -q --allow-empty -m base
printf '# A\n\n## Spec\n\n+ log — Log\n' > a.md
out=$(python3 "$spec" check a.md); assert_exit 1 "TC-13: no About" || fail "TC-13"
assert_contains "$out" "a.md:5: log: no About: line" "TC-13: message" || fail "TC-13: $out"
printf '# A\n\n## Spec\n\n+ log — Log\n  About:\n' > a.md
out=$(python3 "$spec" check a.md); assert_exit 1 "TC-13: empty About" || fail "TC-13 empty"
assert_contains "$out" "a.md:5: log: About: is empty" "TC-13: empty message" || fail "TC-13: $out"

# 14: the record holds Done; the plan's earlier write is verified by the record alone
rw=$(mktemp_dir); cd "$rw" || exit 1
git init -q; git commit -q --allow-empty -m base
cat > p.md <<'P'
# Plan: rw

## Out of scope

- Nothing.

## Done

1. Press "Save" → closed.

## Spec

+ ed — Editor
  About: the form
+ ed#save — Saving closes
  Why: a visit
  Done: 1
P
python3 "$spec" write p.md || fail "TC-14: write"
sed -i.bak 's/→ closed/→ the editor is gone/; s/Saving closes/Saving ends the visit/' p.md; rm p.md.bak
python3 "$spec" write p.md || fail "TC-14: reworded Done item and Spec line, write again"
area=$(cat docs/spec/ed.md)
assert_contains "$area" "### save — Saving ends the visit" "TC-14: the new statement" || fail "TC-14 statement"
assert_contains "$area" "→ the editor is gone" "TC-14: the new scenario" || fail "TC-14 scenario"
[ "$(ls docs/spec/archive | wc -l)" -eq 1 ] || fail "TC-14: one record"
rec=$(cat docs/spec/archive/p.md)
assert_contains "$rec" '## Out of scope

- Nothing.

## Done

1. Press "Save" → the editor is gone.

## Spec' "TC-14: Done between Out of scope and Spec" || fail "TC-14 record: $rec"
echo "a hand edit" >> docs/spec/ed.md
python3 "$spec" write p.md >/dev/null; assert_exit 1 "TC-14: a hand edit is still refused" || fail "TC-14 edit"
git checkout -q -- . 2>/dev/null; python3 - <<'Q'
import re
t=open("docs/spec/ed.md").read().replace("a hand edit\n","")
open("docs/spec/ed.md","w").write(t)
Q
# an uncommitted record without Done: the plan's own Done stands in
python3 - <<'Q'
t=open("docs/spec/archive/p.md").read()
open("docs/spec/archive/p.md","w").write(t.replace('## Done\n\n1. Press "Save" → the editor is gone.\n\n',''))
Q
python3 "$spec" write p.md || fail "TC-14: an old-format record is replaced"
assert_contains "$(cat docs/spec/archive/p.md)" "## Done" "TC-14: now with Done" || fail "TC-14 redo"
# a committed record without Done is valid: no complaint, show lists it
git add -A && git commit -q -m w
python3 - <<'Q'
t=open("docs/spec/archive/p.md").read()
open("docs/spec/archive/p.md","w").write(t.replace('## Done\n\n1. Press "Save" → the editor is gone.\n\n',''))
Q
git commit -q -am old
printf '# Plan: other\n\n## Spec\n\nnone\n' > o.md
python3 "$spec" check o.md; assert_exit 0 "TC-14: a committed record without Done is valid" || fail "TC-14 old"
printf '# Plan: o2\n\n## Done\n\n1. x\n\n## Spec\n\n+ ed#more — More\n  Why: w\n  Done: 1\n' > o2.md
python3 "$spec" write o2.md || fail "TC-14: write over an old-format base"
assert_contains "$(python3 "$spec" show ed#save)" "## archive/p.md — Plan: rw" "TC-14: show lists it" || fail "TC-14 show"

# 15: a plan without a title
nt=$(mktemp_dir); cd "$nt" || exit 1
git init -q; git commit -q --allow-empty -m base
printf '## Done\n\n1. x\n\n## Spec\n\n+ log — Log\n  About: a\n' > n.md
out=$(python3 "$spec" check n.md); assert_exit 1 "TC-15: no title" || fail "TC-15"
assert_contains "$out" "n.md:1: no \`# \` title line" "TC-15: message" || fail "TC-15: $out"
python3 "$spec" write n.md >/dev/null; assert_exit 1 "TC-15: write refuses" || fail "TC-15 write"
[ -z "$(git status --porcelain -uall docs)" ] || fail "TC-15: write wrote"

# 16: a plan whose Spec became `none` puts docs/spec/ back to the base; a hand edit is refused
nn=$(mktemp_dir); cd "$nn" || exit 1
git init -q; git commit -q --allow-empty -m base
printf '# Plan: nn\n\n## Done\n\n1. x\n\n## Spec\n\n+ log — Log\n  About: a\n+ log#r — R\n  Why: y\n  Done: 1\n' > n.md
python3 "$spec" write n.md || fail "TC-16: write"
echo "a hand edit" >> docs/spec/log.md
printf '# Plan: nn\n\n## Spec\n\nnone\n' > n.md
python3 "$spec" write n.md >/dev/null; assert_exit 1 "TC-16: none over a hand edit is refused" || fail "TC-16 edit"
[ -f docs/spec/log.md ] || fail "TC-16: refusal lost the area"
sed -i.bak '$d' docs/spec/log.md; rm docs/spec/log.md.bak
python3 "$spec" write n.md || fail "TC-16: none re-write"
[ -z "$(git status --porcelain -uall docs)" ] || fail "TC-16: docs/spec/ is not the base: $(git status --porcelain -uall docs)"

# 16b: a retitled plan whose Spec is `none` refuses over the first write's files
printf '# Plan: nn\n\n## Done\n\n1. x\n\n## Spec\n\n+ log — Log\n  About: a\n' > n.md
python3 "$spec" write n.md || fail "TC-16b: write"
printf '# Plan: retitled\n\n## Spec\n\nnone\n' > n.md
python3 "$spec" write n.md >/dev/null; assert_exit 1 "TC-16b: retitled none is refused" || fail "TC-16b refuse"
[ -f docs/spec/archive/n.md ] || fail "TC-16b: refusal lost the record"
rm -rf docs
printf '# Plan: retitled\n\n## Spec\n\nnone\n' > n.md
python3 "$spec" write n.md; assert_exit 0 "TC-16b: none over the base is quiet" || fail "TC-16b none"
[ ! -e docs ] || fail "TC-16b: none wrote"

# arguments, base, outside a repo
cd "$repo" || exit 1
python3 "$spec" bogus >/dev/null 2>&1; assert_exit 2 "bad command exits 2" || fail "args"
python3 "$spec" check "$repo/missing.md" >/dev/null 2>&1; assert_exit 2 "missing plan exits 2" || fail "args"
python3 "$spec" check --base nosuchrev "$none" >/dev/null; assert_exit 1 "unknown base exits 1" || fail "base"
cd "$(mktemp_dir)" || exit 1
python3 "$spec" check "$repo/$none" >/dev/null 2>&1; assert_exit 1 "outside a repo exits 1" || fail "outside"
