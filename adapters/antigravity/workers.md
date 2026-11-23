# Dispatch a worker in Antigravity CLI

The bundled Markdown roles contain portable instructions. Antigravity CLI
1.5.15 loads them without file editing or shell tools. For an assignment
requiring either, register a session-local role with `define_subagent` before
the first `invoke_subagent`. Reuse that definition for the same role during
the session.

- Give it a distinct name such as `dev-implementer`. Set `SystemPrompt` to
  the body of the brief's role source. Resolve relative resource links from
  that source's directory.
- Set `EnableWriteTools: true` for editing or shell commands, including CLI
  reports. Keep `EnableSubagentTools: false`. Enable MCP tools only when the
  assignment needs them. The brief still limits which paths the worker edits.
- Invoke the new `TypeName` with the approved executor and the absolute brief
  path. A fresh review or judgment gets its own conversation and role source.
