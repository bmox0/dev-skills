# Optional host adapters

Shared scripts resolve `adapters/<name>/` relative to their package. Names use
lowercase letters, digits and internal hyphens; paths escaping this directory
are refused. Adding an adapter needs no shared host catalogue.

- `scripts/usage --source NAME` imports `adapters/NAME/usage.py`.
  `default_root()` returns that format's native transcript directory.
  `sessions(root, project_filter=None)` yields `(record, messages)` pairs.
  Readers may use the project substring to skip unrelated files; descendants
  needed for a root's totals must still be counted across projects. Shared code
  applies the final project/date filters, ordering, exports and formatting.

Usage records keep the existing fields and `_exact` totals used by the table.
Messages are `(project, session_id, timestamp, text)` tuples. Format parsing and
native roots stay in adapters; timestamp, JSONL and duration helpers live in
`scripts/usage_common.py`. Default checks and fixture tests call no AI clients.
