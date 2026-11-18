"""Codex rollout format and native log root."""

import collections
import datetime
import glob
import json
import os
import re

from usage_common import active_seconds, events, n, timestamp


def read_codex_session(path):
    first = next(events(path), {})
    meta = first.get("payload")
    if first.get("type") != "session_meta" or not isinstance(meta, dict) or not meta.get("id"):
        return None
    source = meta.get("source")
    subagent = source.get("subagent") if isinstance(source, dict) else None
    spawn = subagent.get("thread_spawn", {}) if isinstance(subagent, dict) else {}
    spawn = spawn if isinstance(spawn, dict) else {}
    parent = meta.get("parent_thread_id") or spawn.get("parent_thread_id")
    start = meta.get("subagent_history_start_ordinal", 0)
    start = start if isinstance(start, int) and start >= 0 else 0
    times = [timestamp(meta)] if timestamp(meta) else []
    responses, human_events = [], []
    seen_messages, seen_calls = set(), set()
    agents, totals = collections.Counter(), collections.Counter()
    turn, interrupts = None, 0
    for event in events(path, start):
        p = event.get("payload")
        if not isinstance(p, dict) or event.get("type") == "session_meta":
            continue
        t = timestamp(event)
        if t:
            times.append(t)
        kind = p.get("type")
        if event.get("type") == "turn_context" or kind == "task_started":
            turn = p.get("turn_id", turn)
        if event.get("type") == "event_msg":
            if kind == "token_count":
                info = p.get("info")
                usage = info.get("total_token_usage") if isinstance(info, dict) else None
                if isinstance(usage, dict):
                    # Cached input and reasoning output are subsets of these cumulative counters.
                    for field in ("input_tokens", "output_tokens"):
                        totals[field] = max(totals[field], n(usage.get(field)))
            elif kind == "turn_aborted":
                interrupts += 1
            elif kind == "user_message" and isinstance(p.get("message"), str):
                human_events.append((p.get("turn_id", turn), t, p["message"]))
        if event.get("type") != "response_item":
            continue
        if kind == "function_call" and p.get("name", "").split(".")[-1] == "spawn_agent":
            cid = p.get("call_id") or p.get("id")
            if cid and cid in seen_calls:
                continue
            if cid:
                seen_calls.add(cid)
            try:
                args = json.loads(p.get("arguments", "{}"))
            except (ValueError, TypeError):
                args = {}
            agents[args.get("agent_type", "?") if isinstance(args, dict) else "?"] += 1
        if kind != "message" or p.get("role") != "user":
            continue
        mid = p.get("id")
        if mid and mid in seen_messages:
            continue
        if mid:
            seen_messages.add(mid)
        metadata = p.get("internal_chat_message_metadata_passthrough")
        metadata = metadata if isinstance(metadata, dict) else {}
        kinds = metadata.get("content_item_kinds", [])
        provenance = metadata.get("content_item_metadata", [])
        content = p.get("content")
        parts = []
        human = False
        for i, part in enumerate(content if isinstance(content, list) else []):
            if not isinstance(part, dict):
                continue
            if kinds or provenance:
                k = kinds[i] if i < len(kinds) else ""
                origin = provenance[i].get("provenance", {}) if i < len(provenance) else {}
                if not k.startswith("user.") and origin.get("type") != "user":
                    continue
            text = part.get("text", "")
            if not isinstance(text, str) or text.startswith(("# AGENTS.md", "<environment_context>",
                                                             "<permissions instructions>")):
                continue
            human = True
            parts.append(text)
        if human:
            responses.append((metadata.get("turn_id", turn), t, "\n".join(parts)))
    # Some rollouts store both representations of the same human message.
    duplicates = collections.Counter((turn, text) for turn, _, text in human_events)
    messages = [(t, text) for _, t, text in human_events]
    for turn, t, text in responses:
        if duplicates[(turn, text)]:
            duplicates[(turn, text)] -= 1
        else:
            messages.append((t, text))
    if not times:
        return None
    project, sid = meta.get("cwd", "?"), meta["id"]
    cmds = collections.Counter()
    for _, text in messages:
        command = re.match(r"^/([\w:-]+)(?:\s|$)", text)
        if command:
            cmds[command.group(1)] += 1
    wall = (max(times) - min(times)).total_seconds() / 3600
    active = active_seconds(times) / 3600
    record = {
        "project": project, "sid": sid[:8], "title": None,
        "start": min(times).astimezone(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M"),
        "wall_h": round(wall, 1), "active_h": round(active, 1), "nuser": len(messages),
        "interrupts": interrupts, "skills": {}, "cmds": dict(cmds), "agents": dict(agents),
        "out_k": totals["output_tokens"] // 1000, "in_M": round(totals["input_tokens"] / 1e6, 1),
        "nsubs": 0, "sub_out_k": 0, "sub_h": 0.0,
        "_exact": {"wall_h": wall, "active_h": active, "sub_h": 0.0,
                   "out_k": totals["output_tokens"] / 1000},
    }
    return sid, parent, bool(parent or subagent or meta.get("thread_source") == "subagent"), record, messages


def sessions(root, project_filter=None):
    sessions = {}
    for path in sorted(glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True)):
        session = read_codex_session(path)
        if session:
            sessions[session[0]] = session
    for sid, parent, child, record, _ in sessions.values():
        if not child:
            continue
        visited = {sid}
        while parent in sessions and parent not in visited:
            visited.add(parent)
            _, ancestor, is_child, owner, _ = sessions[parent]
            if not is_child:
                owner["nsubs"] += 1
                owner["sub_out_k"] += record["_exact"]["out_k"]
                owner["_exact"]["sub_h"] += record["_exact"]["wall_h"]
                break
            parent = ancestor
    for sid, _, child, record, messages in sessions.values():
        if not child:
            record["sub_out_k"] = int(record["sub_out_k"])
            record["sub_h"] = round(record["_exact"]["sub_h"], 1)
            yield record, [(record["project"], sid[:8], t, text) for t, text in messages]


def default_root():
    return os.path.join(os.path.expanduser(os.environ.get("CODEX_HOME", "~/.codex")), "sessions")
