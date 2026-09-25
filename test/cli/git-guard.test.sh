#!/usr/bin/env bash
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

. "$repo_root/test/lib/harness.sh"
. "$repo_root/test/lib/gitfixture.sh"

hook="$repo_root/hooks/git-guard.sh"

fail() {
  echo "git-guard.test.sh: $1" >&2
  exit 1
}

run_hook() {
  out=$(jq -cn --arg c "$1" --arg d "$2" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | "$hook")
  rc=$?
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
}

denied() {
  run_hook "$2" "$3"
  assert_eq 0 "$rc" "$1: hook exits 0" || fail "$1"
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 \
    || fail "$1: expected a deny for: $2"
  [ -z "${4:-}" ] || assert_contains "$reason" "$4" "$1: reason names the rule" || fail "$1"
}

allowed() {
  run_hook "$2" "$3"
  assert_eq 0 "$rc" "$1: hook exits 0" || fail "$1"
  assert_eq "" "$out" "$1: no output for an allowed command: $2" || fail "$1"
}

main_repo=$(gitfixture_new)
feat_repo=$(gitfixture_new)
gitfixture_branch "$feat_repo" feat/demo
elsewhere=$(mktemp_dir)

denied TC-1 'git add .' "$feat_repo" "blanket staging"
denied TC-1b 'git add -A' "$feat_repo" "blanket staging"
denied TC-1c 'git add --all' "$feat_repo" "blanket staging"
denied TC-1d 'git status && rtk git add -- .' "$feat_repo" "blanket staging"
allowed TC-1e 'git add README.md hooks/x.sh' "$feat_repo"
denied TC-2 'git commit -am "feat: add x"' "$feat_repo" "git commit -a"
denied TC-2b 'git commit --all -m "feat: add x"' "$feat_repo" "git commit -a"
allowed TC-2c 'git commit --amend -m "feat: add x"' "$feat_repo"
allowed TC-2d "git commit -m'fix: add a'" "$feat_repo"

denied TC-3 'git commit -m "update stuff"' "$feat_repo" "not Conventional"
allowed TC-3b 'git commit -m "ABC-12: fix(hooks): parse heredocs"' "$feat_repo"
subject72="feat: $(printf 'x%.0s' $(seq 1 66))"
allowed TC-4 "git commit -m \"$subject72\"" "$feat_repo"
denied TC-4b "git commit -m \"${subject72}x\"" "$feat_repo" "73 characters"
body301=$(printf 'y%.0s' $(seq 1 301))
denied TC-5 "git commit -F - <<'EOF'
feat: add x

$body301
EOF" "$feat_repo" "301 characters"
denied TC-5b "git commit -m \"\$(cat <<'EOF'
feat: add x

$body301
EOF
)\"" "$feat_repo" "301 characters"
allowed TC-5c "git commit -m \"\$(cat <<'EOF'
feat: add x

Short body.
EOF
)\"" "$feat_repo"
denied TC-5d "git commit -m 'feat: add x' -m '$body301'" "$feat_repo" "characters; the cap is 300"
denied TC-6 "git commit -F - <<'EOF'
feat: add x

Co-Authored-By: Someone <a@b.c>
EOF" "$feat_repo" "attribution"
denied TC-6b 'git commit -m "feat: add x" --trailer "Claude-Session: abc"' "$feat_repo" "attribution"
allowed TC-7 'git commit -m "$MSG"' "$feat_repo"
denied TC-7b 'git commit -m "update \`ref\` in finish"' "$feat_repo" "not Conventional"
allowed TC-7e 'git commit -m "update `date`"' "$feat_repo"
allowed TC-7c "git commit -m 'feat: keep \`ref\` in finish'" "$feat_repo"
allowed TC-7d 'git commit -F msg.txt' "$feat_repo"

allowed TC-8 "cat > notes.md <<'EOF'
git commit -m \"not a subject\"
git add .
git reset --hard
EOF" "$main_repo"
allowed TC-8b 'echo "git add . && git push --force" > notes.txt' "$main_repo"
allowed TC-8c "grep -n 'git commit -a' README.md # && git clean -f" "$main_repo"
denied TC-8d "cat > notes.md <<'EOF'
git add .
EOF
git add -A" "$feat_repo" "blanket staging"

denied TC-9 'git reset --hard HEAD~1' "$feat_repo" "reset --hard"
allowed TC-9b 'git reset --soft HEAD~1' "$feat_repo"
allowed TC-9c 'git reset -- README.md' "$feat_repo"
denied TC-10 'git clean -fdx' "$feat_repo" "clean -f"
allowed TC-10b 'git clean -n' "$feat_repo"
denied TC-11 'git checkout .' "$feat_repo" "checkout ."
denied TC-11b 'git checkout HEAD -- .' "$feat_repo" "checkout ."
allowed TC-11c 'git checkout -- README.md' "$feat_repo"
allowed TC-11d 'git checkout -b feat/other' "$feat_repo"
denied TC-12 'git restore .' "$feat_repo" "restore ."
allowed TC-12b 'git restore --staged .' "$feat_repo"
denied TC-12c 'git restore --staged --worktree .' "$feat_repo" "restore ."
allowed TC-12d 'git restore README.md' "$feat_repo"
denied TC-13 'git branch -D feat/old' "$feat_repo" "branch -D"
denied TC-13b 'git branch --delete --force feat/old' "$feat_repo" "branch -D"
allowed TC-13c 'git branch -d feat/old' "$feat_repo"

denied TC-14 'git push --force origin main' "$feat_repo" "force push to main"
denied TC-14b 'git push origin +main' "$feat_repo" "force push to main"
denied TC-14c 'git push --force-with-lease origin HEAD:main' "$feat_repo" "force push to main"
denied TC-14d 'git push -f' "$main_repo" "force push to main"
allowed TC-14e 'git push --force origin feat/demo' "$feat_repo"
allowed TC-14f 'git push -f' "$feat_repo"
allowed TC-14g 'git push origin main' "$main_repo"

denied TC-15 'git commit -m "feat: add x"' "$main_repo" "default branch"
denied TC-15b "git -C '$main_repo' commit -m 'feat: add x'" "$elsewhere" "default branch"
denied TC-15c "cd '$main_repo' && git commit -m 'feat: add x'" "$elsewhere" "default branch"
allowed TC-15d 'git commit -m "feat: add x"' "$feat_repo"
allowed TC-15e 'git merge --no-ff feat/demo' "$main_repo"
allowed TC-15f 'git commit -m "feat: add x"' "$elsewhere"

direct_repo=$(gitfixture_new)
printf '# Project\n\n## Environment\n\n**Tests.** none\n**main.** direct\n\n## Other\n' > "$direct_repo/CLAUDE.md"
allowed TC-16 'git commit -m "feat: add x"' "$direct_repo"
outside_repo=$(gitfixture_new)
printf '# Project\n\n## Notes\n\n**main.** direct\n' > "$outside_repo/CLAUDE.md"
denied TC-16b 'git commit -m "feat: add x"' "$outside_repo" "default branch"

merging_repo=$(gitfixture_new)
gitfixture_branch "$merging_repo" feat/side
printf 'side\n' > "$merging_repo/README.md"
git -C "$merging_repo" commit -q -am "feat: side"
git -C "$merging_repo" checkout -q main
printf 'main\n' > "$merging_repo/README.md"
git -C "$merging_repo" commit -q -am "feat: main"
git -C "$merging_repo" merge -q feat/side >/dev/null 2>&1
git -C "$merging_repo" rev-parse -q --verify MERGE_HEAD >/dev/null || fail "TC-17: fixture should be mid-merge"
allowed TC-17 'git commit -m "fix: resolve the merge"' "$merging_repo"

unborn=$(mktemp_dir)
git -C "$unborn" init -q -b main
allowed TC-18 'git commit -m "chore: initial commit"' "$unborn"

detached=$(gitfixture_new)
git -C "$detached" checkout -q --detach
allowed TC-19 'git commit -m "feat: add x"' "$detached"

printf 'not json' | "$hook" >/dev/null
assert_exit 0 "TC-20: garbage on stdin exits 0" || fail "TC-20"
out=$(printf 'not json with git in it' | "$hook")
assert_eq "" "$out" "TC-20b: garbage prints nothing" || fail "TC-20b"
allowed TC-20c 'ls -la' "$feat_repo"

denied TC-21 'git status && git checkout main && git commit -m "feat: add x"' "$feat_repo" "a commit on main"
denied TC-21b 'git switch main && git merge --squash feat/demo && git commit -m "feat: add x"' "$feat_repo" "a commit on main"
allowed TC-21c 'git switch -c feat/x && git commit -m "feat: add x"' "$main_repo"
allowed TC-21d "git checkout -b fix/y && git add a.txt && git commit -m 'fix: y'" "$main_repo"
allowed TC-21e 'git checkout -- README.md && git commit -m "feat: add x"' "$feat_repo"

denied TC-22 'cd "$X" && git commit -m "feat: ok" && git reset --hard HEAD~3' "$feat_repo" "reset --hard"
denied TC-22b 'git commit -m "feat: ok" && git -C "$DIR" push -f origin main' "$feat_repo" "force push to main"

tab=$(printf '\t')
allowed TC-23 "git commit -F - <<-EOF
${tab}feat: add x
${tab}EOF" "$feat_repo"
denied TC-23b "git commit -F - <<-EOF
${tab}update stuff
${tab}EOF" "$feat_repo" "not Conventional"
denied TC-23c 'git commit -F - <<< "update stuff"' "$feat_repo" "not Conventional"
allowed TC-23d "git commit -m \$'feat: add x\\n\\nWhy it changed.'" "$feat_repo"
denied TC-23e "git commit -m \$'update\\n'" "$feat_repo" "not Conventional"

denied TC-24 'git add ./' "$feat_repo" "blanket staging"
denied TC-24b 'git add -- :/' "$feat_repo" "blanket staging"
denied TC-24c 'git add -u' "$feat_repo" "blanket staging"
allowed TC-24d 'git add -u src/' "$feat_repo"
allowed TC-24e 'git add -n .' "$feat_repo"
denied TC-24f "git commit -m 'feat: add x' -- ." "$feat_repo" "pathspec ."
allowed TC-24g 'git clean -f -n' "$feat_repo"
denied TC-24h 'env GIT_EDITOR=true git add .' "$feat_repo" "blanket staging"
denied TC-24i 'time git add -A' "$feat_repo" "blanket staging"

denied TC-25 "git commit -S -am 'feat: add x'" "$feat_repo" "git commit -a"
denied TC-25b "git commit -S -m 'update stuff'" "$feat_repo" "not Conventional"

fenced_repo=$(gitfixture_new)
printf '\xef\xbb\xbf## Environment\n\n```bash\n# install deps\nnpm ci\n```\n\n**main.** direct\n' > "$fenced_repo/CLAUDE.md"
allowed TC-26 'git commit -m "feat: add x"' "$fenced_repo"

allowed TC-27 "git commit -m 'fix(hooks): stop stripping Co-Authored-By from docs'" "$feat_repo"
denied TC-27b "git commit -F - <<'EOF'
feat: add x

Generated with Claude Code
EOF" "$feat_repo" "attribution"
denied TC-27c "git commit -m 'feat: add x 🤖'" "$feat_repo" "attribution"
body300=$(printf 'z%.0s' $(seq 1 300))
allowed TC-27d "git commit -m 'feat: add x' -m '$body300'" "$feat_repo"

denied TC-28 'git push -f origin @' "$main_repo" "force push to main"
denied TC-28b "git push -f origin 'refs/heads/*:refs/heads/*'" "$feat_repo" "force push to main"
allowed TC-28c 'git push --tags --force' "$main_repo"

remote_repo=$(gitfixture_new)
git -C "$remote_repo" update-ref refs/remotes/origin/develop HEAD
git -C "$remote_repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop
git -C "$remote_repo" branch -q develop
allowed TC-29 'git commit -m "feat: add x"' "$remote_repo"
git -C "$remote_repo" checkout -q develop
denied TC-29b 'git commit -m "feat: add x"' "$remote_repo" "a commit on develop"

denied TC-31 'git commit -m "feat: $SUMMARY" -m "Co-Authored-By: Claude <noreply@anthropic.com>"' "$feat_repo" "attribution"
denied TC-31b 'git commit -m "feat: add x" --trailer "Assisted-by: Claude 🤖"' "$feat_repo" "attribution"
denied TC-31c "git commit -m \"\$(cat <<'EOF'
feat: add x

Generated with [Claude Code](https://claude.com/claude-code)
EOF
)\"" "$feat_repo" "attribution"

denied TC-32 'git checkout HEAD~1 README.md && git commit -m "fix: revert readme"' "$main_repo" "a commit on main"
allowed TC-32b 'git checkout main README.md && git commit -m "fix: restore readme"' "$feat_repo"
allowed TC-32c 'git checkout -p main && git commit -m "fix: pick hunks"' "$feat_repo"
mkdir -p "$main_repo/sub" "$feat_repo/sub"
denied TC-32d 'git switch main && cd sub && git commit -m "feat: add x"' "$feat_repo" "a commit on main"
allowed TC-32e 'git switch -c feat/x && cd sub && git commit -m "feat: add x"' "$main_repo"
allowed TC-32f 'git branch feat/y && git checkout feat/y && git commit -m "feat: add y"' "$main_repo"
denied TC-32g 'git checkout main && git push -f' "$feat_repo" "force push to main"

allowed TC-33 "git push --force origin 'refs/tags/*'" "$feat_repo"
allowed TC-33b "git push --force origin 'feat/*'" "$feat_repo"

tilde_repo=$(gitfixture_new)
printf '## Environment\n\n~~~bash\n# install deps\n~~~\n\n**main.** direct\n' > "$tilde_repo/CLAUDE.md"
allowed TC-34 'git commit -m "feat: add x"' "$tilde_repo"

nopy=$(mktemp_dir)
for tool in bash cat dirname; do ln -s "$(command -v "$tool")" "$nopy/$tool"; done
out=$(jq -cn --arg c 'git add .' --arg d "$feat_repo" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' \
  | PATH="$nopy" "$hook")
assert_eq "" "$out" "TC-30: with no python3 the hook allows" || fail "TC-30"

exit 0
