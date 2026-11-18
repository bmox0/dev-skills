"""Claude Code transcript format and native log root."""

import collections
import glob
import os
import re

from usage_common import active_seconds, events, n, timestamp


def user_text(event):
    m = event.get("message")
    if not isinstance(m, dict) or m.get("role") != "user":
        return None
    content = m.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        if any(isinstance(x, dict) and x.get("type") == "tool_result" for x in content):
            return None
        parts = [x.get("text", "") for x in content if isinstance(x, dict) and x.get("type") == "text"]
        parts = [part for part in parts if isinstance(part, str)]
        return "\n".join(parts) if parts else None
    return None


TOKEN_FIELDS = ("output_tokens", "input_tokens", "cache_read_input_tokens",
                "cache_creation_input_tokens")


class Tokens:
    def __init__(self):
        self.by_id = {}
        self.anonymous = collections.Counter()

    def add(self, message):
        u = message.get("usage")
        if not isinstance(u, dict):
            return
        mid = message.get("id")
        if not mid:
            for field in TOKEN_FIELDS:
                self.anonymous[field] += n(u.get(field))
            return
        best = self.by_id.setdefault(mid, collections.Counter())
        for field in TOKEN_FIELDS:
            best[field] = max(best[field], n(u.get(field)))

    def total(self, *fields):
        return sum(self.anonymous[f] + sum(c[f] for c in self.by_id.values()) for f in fields)


def read_session(project, path):
    sid = os.path.basename(path)[:-len(".jsonl")]
    title = None
    times = []
    skills, agents, cmds = collections.Counter(), collections.Counter(), collections.Counter()
    messages = []
    interrupts = 0
    tokens = Tokens()
    for event in events(path):
        if event.get("type") == "ai-title":
            title = event.get("aiTitle") or event.get("title") or title
        if event.get("isSidechain"):
            continue
        t = timestamp(event)
        if t:
            times.append(t)
        m = event.get("message")
        if event.get("type") == "assistant" and isinstance(m, dict):
            tokens.add(m)
            content = m.get("content")
            for c in content if isinstance(content, list) else []:
                if isinstance(c, dict) and c.get("type") == "tool_use":
                    tool_input = c.get("input") if isinstance(c.get("input"), dict) else {}
                    if c.get("name") == "Skill":
                        skills[tool_input.get("skill")] += 1
                    if c.get("name") in ("Agent", "Task"):
                        agents[tool_input.get("subagent_type", "?")] += 1
        if event.get("type") != "user":
            continue
        text = user_text(event)
        if text is None:
            continue
        if "[Request interrupted" in text:
            interrupts += 1
            continue
        for name in re.findall(r"<command-name>/?([^<]+)</command-name>", text):
            cmds[name.strip()] += 1
        if event.get("isMeta"):
            continue
        if text.startswith("<") and any(k in text for k in (
                "command-name", "local-command", "system-reminder", "task-notification")):
            if "command-name" in text:
                args = re.search(r"<command-args>(.*?)</command-args>", text, re.S)
                names = " ".join(re.findall(r"<command-name>([^<]+)", text))
                messages.append((t, "CMD " + names + " " + (args.group(1)[:300] if args else "")))
            continue
        messages.append((t, text))

    subs = glob.glob(os.path.join(os.path.dirname(path), sid, "subagents", "*.jsonl"))
    sub_out = 0
    sub_seconds = 0.0
    for sub in subs:
        st = []
        sub_tokens = Tokens()
        for event in events(sub):
            t = timestamp(event)
            if t:
                st.append(t)
            m = event.get("message")
            if event.get("type") == "assistant" and isinstance(m, dict):
                sub_tokens.add(m)
        sub_out += sub_tokens.total("output_tokens")
        if st:
            sub_seconds += (max(st) - min(st)).total_seconds()

    if not times:
        return None, []
    out_tokens = tokens.total("output_tokens")
    in_tokens = tokens.total("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")
    wall = (max(times) - min(times)).total_seconds()
    active = active_seconds(times)
    record = {
        "project": project,
        "sid": sid[:8],
        "title": title,
        "start": min(times).strftime("%Y-%m-%d %H:%M"),
        "wall_h": round(wall / 3600, 1),
        "active_h": round(active / 3600, 1),
        "nuser": len(messages),
        "interrupts": interrupts,
        "skills": dict(skills),
        "cmds": dict(cmds),
        "agents": dict(agents),
        "out_k": out_tokens // 1000,
        "in_M": round(in_tokens / 1e6, 1),
        "nsubs": len(subs),
        "sub_out_k": sub_out // 1000,
        "sub_h": round(sub_seconds / 3600, 1),
        "_exact": {"wall_h": wall / 3600, "active_h": active / 3600, "sub_h": sub_seconds / 3600,
                   "out_k": out_tokens / 1000},
    }
    return record, [(project, sid[:8], t, text) for t, text in messages]


def default_root():
    return os.path.expanduser("~/.claude/projects")


def sessions(root, project_filter=None):
    for project in sorted(os.listdir(root)):
        if project_filter and project_filter not in project:
            continue
        for path in sorted(glob.glob(os.path.join(root, project, "*.jsonl"))):
            yield read_session(project, path)
