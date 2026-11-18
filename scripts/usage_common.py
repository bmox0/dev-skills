"""Transcript primitives shared by optional format readers."""

import datetime
import json

GAP_SECONDS = 900


def timestamp(event):
    t = event.get("timestamp")
    if not isinstance(t, str) or not t:
        return None
    try:
        parsed = datetime.datetime.fromisoformat(t.replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=datetime.timezone.utc)


def active_seconds(times):
    times = sorted(t for t in times if t)
    return sum(
        (b - a).total_seconds()
        for a, b in zip(times, times[1:])
        if (b - a).total_seconds() < GAP_SECONDS
    )


def events(path, start=0):
    with open(path, encoding="utf-8", errors="replace") as f:
        for ordinal, line in enumerate(f):
            if ordinal < start:
                continue
            try:
                event = json.loads(line)
            except ValueError:
                continue
            if isinstance(event, dict):
                yield event


def n(value):
    return value if isinstance(value, (int, float)) else 0


