#!/usr/bin/env python3
import fnmatch
import json
import os
import re
import subprocess
import sys

CONVENTIONAL = re.compile(
    r"^(([A-Z][A-Z0-9]*-[0-9]+|#[0-9]+):?\s+)?"
    r"(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)"
    r"(\([a-zA-Z0-9._/-]+\))?!?: .+"
)
BANNED_LINE = re.compile(r"^\s*(co-authored-by|claude-session)\s*[:=]", re.I | re.M)
BANNED_ANY = re.compile(r"generated with \[?claude code|\U0001F916", re.I)
CONTROL = ("&&", "||", ";;", "|&", ";", "&", "|", "(", ")")
REDIRECTS = ("<<<", "&>>", "&>", ">>", ">|", ">&", "<&", "<>", ">", "<")
DYNAMIC = "\x00"
PREFIXES = {"!", "{", "if", "then", "else", "elif", "do", "while", "until", "time",
            "command", "builtin", "exec", "nohup"}
GIT_OPTS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"}
WHOLE_TREE = {".", "./", ":/", ":/."}


class Cmd:
    def __init__(self):
        self.words = []
        self.stdin = []


def skip_heredoc(s, i, delim, strip_tabs, body=None):
    n = len(s)
    while i < n:
        j = s.find("\n", i)
        if j < 0:
            j = n
        line = s[i:j]
        i = j + 1
        if strip_tabs:
            line = line.lstrip("\t")
        if line == delim:
            return i
        if body is not None:
            body.append(line)
    return n


def heredoc_delim(s, i):
    strip = s.startswith("-", i)
    if strip:
        i += 1
    while i < len(s) and s[i] in " \t":
        i += 1
    m = re.match(r"""(['"]?)\\?([^\s'"();&|<>\\]+)\1""", s[i:])
    if not m:
        return None
    return m.group(2), strip, i + m.end()


def scan_backtick(s, i):
    n = len(s)
    while i < n:
        if s[i] == "\\":
            i += 2
            continue
        if s[i] == "`":
            return i + 1
        i += 1
    return n


def scan_dquote(s, i):
    n = len(s)
    while i < n:
        c = s[i]
        if c == "\\":
            i += 2
        elif c == '"':
            return i + 1
        elif s.startswith("$(", i):
            i = scan_subst(s, i + 2)
        elif c == "`":
            i = scan_backtick(s, i + 1)
        else:
            i += 1
    return n


def scan_subst(s, i):
    n = len(s)
    depth = 1
    pending = []
    while i < n:
        c = s[i]
        if c == "\\":
            i += 2
            continue
        if c == "'":
            j = s.find("'", i + 1)
            i = n if j < 0 else j + 1
            continue
        if c == '"':
            i = scan_dquote(s, i + 1)
            continue
        if c == "`":
            i = scan_backtick(s, i + 1)
            continue
        if s.startswith("<<", i) and not s.startswith("<<<", i):
            d = heredoc_delim(s, i + 2)
            if d:
                pending.append(d[:2])
                i = d[2]
                continue
        if c == "\n" and pending:
            i += 1
            for delim, strip in pending:
                i = skip_heredoc(s, i, delim, strip)
            pending = []
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return n


def ansi_c(s, i):
    out = []
    n = len(s)
    escapes = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", "'": "'", '"': '"'}
    while i < n:
        c = s[i]
        if c == "\\" and i + 1 < n:
            out.append(escapes.get(s[i + 1], "\\" + s[i + 1]))
            i += 2
        elif c == "'":
            return "".join(out), i + 1
        else:
            out.append(c)
            i += 1
    return "".join(out), n


def is_expansion(s, i):
    return s[i] == "$" and i + 1 < len(s) and (s[i + 1].isalnum() or s[i + 1] in "_{@*#?$!-")


def dquote(s, i):
    out = []
    n = len(s)
    while i < n:
        c = s[i]
        if c == "\\" and i + 1 < n:
            nxt = s[i + 1]
            if nxt in '"\\$`':
                out.append(nxt)
            elif nxt != "\n":
                out.append("\\" + nxt)
            i += 2
        elif c == '"':
            return "".join(out), i + 1
        elif s.startswith("$(", i):
            j = scan_subst(s, i + 2)
            out.append(DYNAMIC + s[i:j])
            i = j
        elif c == "`":
            j = scan_backtick(s, i + 1)
            out.append(DYNAMIC + s[i:j])
            i = j
        elif is_expansion(s, i):
            out.append(DYNAMIC + c)
            i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out), n


def parse(s):
    cmds = []
    state = {"cmd": Cmd(), "word": None, "redirect": None}
    pending = []

    def end_word():
        word, redirect = state["word"], state["redirect"]
        if word is None:
            return
        state["word"] = None
        state["redirect"] = None
        if redirect is None:
            state["cmd"].words.append(word)
        elif redirect == "<<<":
            state["cmd"].stdin.append(word + "\n")

    def end_cmd():
        end_word()
        state["redirect"] = None
        if state["cmd"].words:
            cmds.append(state["cmd"])
        state["cmd"] = Cmd()

    def before_redirect():
        word = state["word"]
        if word is not None and word.isdigit() and state["redirect"] is None:
            state["word"] = None
        else:
            end_word()

    def add(text):
        state["word"] = (state["word"] or "") + text

    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if c == "\\":
            if i + 1 < n and s[i + 1] != "\n":
                add(s[i + 1])
            i += 2
        elif c == "'":
            j = s.find("'", i + 1)
            j = n if j < 0 else j
            add(s[i + 1:j])
            i = j + 1
        elif s.startswith("$'", i):
            text, i = ansi_c(s, i + 2)
            add(text)
        elif c == '"':
            text, i = dquote(s, i + 1)
            add(text)
        elif s.startswith("$(", i):
            j = scan_subst(s, i + 2)
            add(DYNAMIC + s[i:j])
            i = j
        elif c == "`":
            j = scan_backtick(s, i + 1)
            add(DYNAMIC + s[i:j])
            i = j
        elif is_expansion(s, i):
            add(DYNAMIC + c)
            i += 1
        elif c == "#" and state["word"] is None:
            j = s.find("\n", i)
            i = n if j < 0 else j
        elif c in " \t":
            end_word()
            i += 1
        elif c == "\n":
            end_cmd()
            i += 1
            for cmd, delim, strip in pending:
                body = []
                i = skip_heredoc(s, i, delim, strip, body)
                cmd.stdin.append("\n".join(body) + "\n")
            pending = []
        elif s.startswith("<<", i) and not s.startswith("<<<", i):
            before_redirect()
            d = heredoc_delim(s, i + 2)
            if d:
                pending.append((state["cmd"], d[0], d[1]))
                i = d[2]
            else:
                i += 2
        else:
            op = next((o for o in REDIRECTS if s.startswith(o, i)), None)
            if op:
                before_redirect()
                state["redirect"] = op
                i += len(op)
                continue
            op = next((o for o in CONTROL if s.startswith(o, i)), None)
            if op:
                end_cmd()
                i += len(op)
            else:
                add(c)
                i += 1
    end_cmd()
    return cmds


def strip_prefixes(words):
    i = 0
    while i < len(words):
        w = words[i]
        if w in PREFIXES or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w):
            i += 1
        elif w == "rtk":
            i += 2 if i + 1 < len(words) and words[i + 1] == "proxy" else 1
        elif w == "env":
            i += 1
            while i < len(words) and (words[i].startswith("-") or "=" in words[i]):
                i += 2 if words[i] in ("-u", "-C", "-S") else 1
        else:
            break
    return words[i:]


def git_parts(args):
    dirs = []
    i = 0
    while i < len(args):
        a = args[i]
        if a in GIT_OPTS_WITH_VALUE:
            if a == "-C" and i + 1 < len(args):
                dirs.append(args[i + 1])
            i += 2
        elif a.startswith("-"):
            i += 1
        else:
            return a, args[i + 1:], dirs
    return None, [], dirs


def split_opts(args, takes_value=(), short_with_value="", short_attached=""):
    flags, values, positional = set(), {}, []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--":
            positional.extend(args[i + 1:])
            break
        if a.startswith("--"):
            name, eq, val = a.partition("=")
            if not eq and name in takes_value:
                i += 1
                val = args[i] if i < len(args) else ""
            flags.add(name)
            values.setdefault(name, []).append(val)
        elif a.startswith("-") and len(a) > 1:
            for k, ch in enumerate(a[1:], start=1):
                flags.add("-" + ch)
                if ch in short_with_value or ch in short_attached:
                    val = a[k + 1:]
                    if not val and ch in short_with_value:
                        i += 1
                        val = args[i] if i < len(args) else ""
                    values.setdefault("-" + ch, []).append(val)
                    break
        else:
            positional.append(a)
        i += 1
    return flags, values, positional


def git(d, *args):
    try:
        r = subprocess.run(["git", "-C", d] + list(args), capture_output=True,
                           text=True, timeout=5)
    except (OSError, ValueError, subprocess.SubprocessError):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def current_branch(d):
    return git(d, "symbolic-ref", "--quiet", "--short", "HEAD")


def default_branch(d, remote="origin"):
    ref = git(d, "symbolic-ref", "--quiet", "--short", "refs/remotes/%s/HEAD" % remote)
    if ref:
        return ref.split("/", 1)[1] if "/" in ref else ref
    for name in ("main", "master"):
        if git(d, "show-ref", "--verify", "--quiet", "refs/heads/" + name) is not None:
            return name
    return "main"


def main_is_direct(d):
    root = git(d, "rev-parse", "--show-toplevel")
    if not root:
        return False
    for rel in ("CLAUDE.md", os.path.join(".claude", "CLAUDE.md")):
        try:
            with open(os.path.join(root, rel), encoding="utf-8-sig") as f:
                text = f.read()
        except (OSError, UnicodeDecodeError):
            continue
        in_env = False
        fence = None
        for line in text.splitlines():
            f = re.match(r"^\s*(`{3,}|~{3,})", line)
            if f:
                if fence is None:
                    fence = f.group(1)
                elif f.group(1)[0] == fence[0] and len(f.group(1)) >= len(fence):
                    fence = None
                continue
            m = None if fence else re.match(r"^(#{1,6})\s+(.*?)\s*$", line)
            if m and len(m.group(1)) <= 2:
                in_env = m.group(2).lower() == "environment"
            elif in_env and re.match(r"^\*\*main\.\*\*\s+`?direct\b", line.strip(), re.I):
                return True
    return False


def resolve_message(value):
    if DYNAMIC not in value:
        return value
    m = re.match(r"^\x00\$\(\s*cat\s*<<(-?)\s*(['\"]?)\\?(\w+)\2[^\n]*\n", value)
    if not m or value.count(DYNAMIC) > 1:
        return None
    body = []
    skip_heredoc(value, m.end(), m.group(3), m.group(1) == "-", body)
    return "\n".join(body)


def commit_message(cmd, flags, values):
    if "-F" in values or "--file" in values:
        src = (values.get("-F") or values.get("--file"))[-1]
        if src != "-" or not cmd.stdin:
            return None
        return cmd.stdin[0]
    parts = values.get("-m", []) + values.get("--message", [])
    if not parts:
        return None
    resolved = [resolve_message(p) for p in parts]
    if any(p is None for p in resolved):
        return None
    return "\n\n".join(resolved)


def check_message(msg):
    lines = [line.rstrip() for line in msg.split("\n")]
    while lines and not lines[0]:
        lines.pop(0)
    while lines and not lines[-1]:
        lines.pop()
    if not lines:
        return None
    subject, body = lines[0], lines[1:]
    while body and not body[0]:
        body.pop(0)
    if not CONVENTIONAL.match(subject):
        return ("the subject '%s' is not Conventional Commits. Use 'type(scope): summary' with a "
                "type from feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert, optionally "
                "after a ticket prefix like 'ABC-123:' or '#123'." % subject)
    if len(subject) > 72:
        return "the subject is %d characters; the cap is 72." % len(subject)
    body_len = len("\n".join(body))
    if body_len > 300:
        return ("the body is %d characters; the cap is 300. Most commits need no body; keep only "
                "why it changed and what the diff cannot show." % body_len)
    return None


def has_banned(texts):
    return any(BANNED_ANY.search(t) or BANNED_LINE.search(t) for t in texts)


def repo_key(d):
    return git(d, "rev-parse", "--show-toplevel") or os.path.normpath(d)


def branch_in(d, switched):
    key = repo_key(d)
    return switched[key] if key in switched else current_branch(d)


def check_commit(cmd, args, d, switched):
    flags, values, positional = split_opts(
        args,
        takes_value={"--message", "--file", "--author", "--date", "--reuse-message",
                     "--reedit-message", "--fixup", "--squash", "--template", "--cleanup",
                     "--trailer", "--pathspec-from-file"},
        short_with_value="mFCct",
        short_attached="uS",
    )
    if "-a" in flags or "--all" in flags or WHOLE_TREE & set(positional):
        return ("git commit -a (or with the pathspec .) commits every tracked change, including "
                "another agent's. Stage your own paths by name, then commit.")
    msg = commit_message(cmd, flags, values)
    texts = (values.get("-m", []) + values.get("--message", []) + values.get("--trailer", [])
             + cmd.stdin + ([msg] if msg is not None else []))
    if has_banned(texts):
        return ("the commit carries an attribution trailer (Co-Authored-By, 'Generated with "
                "Claude Code', Claude-Session or the robot emoji). Remove it.")
    if msg is not None:
        problem = check_message(msg)
        if problem:
            return problem
    key = repo_key(d)
    branch = switched[key] if key in switched else current_branch(d)
    if not branch or branch != default_branch(d):
        return None
    if key not in switched and git(d, "rev-parse", "--verify", "--quiet", "HEAD") is None:
        return None
    if git(d, "rev-parse", "--verify", "--quiet", "MERGE_HEAD") is not None:
        return None
    if main_is_direct(d):
        return None
    return ("a commit on %s, the default branch. Work goes on its own branch: "
            "git switch -c feat/<unit> (or fix/<bug>), then commit; the default branch changes "
            "through /finish. A project that commits to it directly says so with "
            "'**main.** direct' in the ## Environment block of its CLAUDE.md." % branch)


def check_push(args, d, switched):
    flags, values, positional = split_opts(
        args, takes_value={"--repo", "--push-option", "--receive-pack", "--exec"},
        short_with_value="o")
    forced = bool(flags & {"-f", "--force", "--force-with-lease", "--mirror"})
    remote = positional[0] if positional else "origin"
    refspecs = positional[1:]
    everything = bool(flags & {"--all", "--branches", "--mirror"})
    targets = []
    for spec in refspecs:
        plus = spec.startswith("+")
        spec = spec.lstrip("+")
        dst = spec.split(":", 1)[1] if ":" in spec else spec
        if not dst:
            continue
        if dst.startswith("refs/heads/"):
            dst = dst[len("refs/heads/"):]
        if dst in ("HEAD", "@"):
            dst = branch_in(d, switched) or ""
        if dst.startswith("refs/"):
            continue
        targets.append((dst, plus))
    if not refspecs and not everything and "--tags" not in flags:
        targets.append((branch_in(d, switched) or "", False))
    if not forced and not any(plus for _, plus in targets):
        return None
    main = default_branch(d, remote if re.match(r"^[\w.-]+$", remote) else "origin")
    if everything or any(fnmatch.fnmatchcase(main, dst) and (forced or plus)
                         for dst, plus in targets):
        return "a force push to %s, the default branch. Push to a branch of your own." % main
    return None


def switch_target(sub, args, d):
    if sub == "switch":
        flags, values, positional = split_opts(
            args, takes_value={"--create", "--force-create", "--orphan"}, short_with_value="cC")
        for opt in ("-c", "-C", "--create", "--force-create", "--orphan"):
            if opt in values:
                return values[opt][-1]
        if flags & {"-d", "--detach"} or not positional or positional[0] == "-":
            return None
        return positional[0]
    flags, values, positional = split_opts(
        args, takes_value={"--orphan", "--pathspec-from-file"}, short_with_value="bB")
    for opt in ("-b", "-B", "--orphan"):
        if opt in values:
            return values[opt][-1]
    if "--" in args or len(positional) > 1 or flags & {"-p", "--patch", "--pathspec-from-file"}:
        return False
    if "--detach" in flags or not positional or positional[0] == "-":
        return None
    if git(d, "show-ref", "--verify", "--quiet", "refs/heads/" + positional[0]) is not None:
        return positional[0]
    if git(d, "rev-parse", "--verify", "--quiet", positional[0] + "^{commit}") is not None:
        return None
    if os.path.exists(os.path.join(d, positional[0])):
        return False
    return positional[0]


def check_git(cmd, words, d, switched):
    sub, args, dirs = git_parts(words[1:])
    for extra in dirs:
        d = os.path.join(d, os.path.expanduser(extra))
    if sub == "add":
        flags, _, positional = split_opts(args)
        if flags & {"-n", "--dry-run"}:
            return None
        update_all = flags & {"-u", "--update"} and not positional \
            and "--pathspec-from-file" not in flags
        if flags & {"-A", "--all"} or WHOLE_TREE & set(positional) or update_all:
            return ("blanket staging (git add . / -A / -u). Stage the paths you changed "
                    "by name, or use git add -p.")
    elif sub == "commit":
        return check_commit(cmd, args, d, switched)
    elif sub in ("switch", "checkout"):
        if sub == "checkout":
            _, _, positional = split_opts(args, takes_value={"--orphan"}, short_with_value="bB")
            if WHOLE_TREE & set(positional):
                return ("git checkout . discards every uncommitted change in the tree. Restore "
                        "the paths you mean by name.")
        target = switch_target(sub, args, d)
        if target is not False:
            switched[repo_key(d)] = target
    elif sub == "reset":
        flags, _, _ = split_opts(args)
        if "--hard" in flags:
            return ("git reset --hard throws away uncommitted work. Keep it with "
                    "git reset --keep or --soft, or ask the user to run it themselves.")
    elif sub == "clean":
        flags, _, _ = split_opts(args, short_with_value="e")
        if flags & {"-f", "--force"} and not flags & {"-n", "--dry-run"}:
            return ("git clean -f deletes untracked files git cannot give back. Remove them by "
                    "name, or ask the user to run it themselves.")
    elif sub == "restore":
        flags, _, positional = split_opts(args, takes_value={"--source"}, short_with_value="s")
        staged_only = bool(flags & {"-S", "--staged"}) and not flags & {"-W", "--worktree"}
        if WHOLE_TREE & set(positional) and not staged_only:
            return ("git restore . discards every uncommitted change in the tree. Restore the "
                    "paths you mean by name.")
    elif sub == "branch":
        flags, _, _ = split_opts(args)
        delete = bool(flags & {"-d", "--delete"})
        force = bool(flags & {"-f", "--force"})
        if "-D" in flags or (delete and force):
            return ("git branch -D deletes a branch whether or not it is merged. Use "
                    "git branch -d, which refuses an unmerged one.")
    elif sub == "push":
        return check_push(args, d, switched)
    return None


def check(command, cwd):
    d = cwd
    switched = {}
    for cmd in parse(command):
        try:
            words = strip_prefixes(cmd.words)
            if not words:
                continue
            name = os.path.basename(words[0])
            if name in ("cd", "pushd"):
                target = next((w for w in words[1:] if not w.startswith("-")), "~")
                d = os.path.join(d, os.path.expanduser(target))
            elif name == "git":
                problem = check_git(cmd, words, d, switched)
                if problem:
                    return problem
        except Exception:
            continue
    return None


def main():
    try:
        data = json.load(sys.stdin)
        command = (data.get("tool_input") or {}).get("command") or ""
        cwd = data.get("cwd") or os.getcwd()
        problem = check(command, cwd) if command else None
    except Exception:
        return
    if problem:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "Blocked by git-guard: " + problem,
        }}))


if __name__ == "__main__":
    main()
