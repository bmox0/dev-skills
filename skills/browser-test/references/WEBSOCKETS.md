# Recording a socket

`ws [secs] [--reload]` records WebSocket frames through CDP, and it is the one command that reads traffic rather than driving the UI. **Run it only when the question is about the feed** — it is never part of a routine check.

It attaches to worker targets as well as the page, which is often the only way to see anything: a client that picks a worker implementation whenever `Worker` exists puts the socket somewhere nothing on the main thread can observe.

Reading the output: outgoing frames are plain text and readable as sent. Incoming frames are frequently `permessage-deflate` binary — by default only frame count and byte total mean anything, and `--inflate` decodes them:

```bash
tab ws 20 --reload --inflate --grep '"type":"position"'
```

That extension compresses a whole connection as one stream, so a frame only decodes when every frame before it was captured too — **`--inflate` needs `--reload`**, and the tool says so rather than guessing when it cannot decode. Pair it with `--grep` (a regex over the decoded text); without one it prints the first few frames. Snapshots are large, so grep for what you came for.

Cheaper first stop: if the app logs its own frames to the console, `logs --grep <pattern>` answers the question with no recording at all. Reach for `--inflate` when you need a frame the app does not log. Use `--reload` when you need the handshake — CDP cannot name a socket that was already open, though the tool caches `requestId → url` and labels it next time. Query strings are stripped everywhere, so session tokens never reach the output or the cache file.
