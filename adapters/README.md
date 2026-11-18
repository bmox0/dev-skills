# Optional host adapters

Shared scripts resolve `adapters/<name>/` relative to their package. Names use
lowercase letters, digits and internal hyphens; paths escaping this directory
are refused. Adding an adapter needs no shared host catalogue.

- `scripts/check --host NAME` runs `python3 adapters/NAME/validate.py ROOT`.
  Validators exit nonzero when required verification is unavailable or fails.
  Output names the native version and coverage performed (for example,
  manifest or loader validation), including what remains unverified.
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

## Native registrations and coverage

Each native manifest selects `./adapters/<host>/hooks.json`. Claude commands use
`CLAUDE_PLUGIN_ROOT`, Codex uses `PLUGIN_ROOT` (its documented native root), and
Qoder uses `QODER_PLUGIN_ROOT`. The three registrations call `adapters/hooks.py`,
which translates their compatible event/tool envelope to the common
`hooks/advise.py` contract and wraps advice for native `additionalContext`.
There is no implicit native registration in the common handler. Launch failures,
malformed input and unrelated events are quiet exit 0; mandatory CLI checks,
approvals and acceptance remain required with every hook disabled.

The complete package includes `skills/`, `agents/`, `references/`, `scripts/`,
`hooks/` and `adapters/`, with native manifests at the root. Preserve relative
paths and executable modes. A native worker reads the authoritative shared role
and generated absolute brief/protocol paths. Root sessions coordinate; worker
roles keep their assignment and report commands and dispatch nobody. Target
project profiles, plan artifacts and worktrees do not belong in installed code.

| Selection | Native evidence collected | Not established by that check |
|---|---|---|
| `--host claude` | Actual client version; strict marketplace/plugin manifest validation | Installed revision, live roles/model/handoff |
| `--host codex` | Actual client version; temporary native install and model-visible skill inventory | Live custom-role equivalence, model routing, trusted hook execution |
| `--host qoder` | Actual client version; native manifest validation, selected package path/version, full skill/role/hook inventory | Native role dispatch, requested/effective settings, continuation or workflow finish |
| Default checks/tests | Shared resource checks; executable fixtures; relocated complete package | Installed native clients or live inference |

Qoder supports native `--agent dev-skills:<role>` and explicit `--model`;
`--reasoning-effort` is optional. Read frozen executor headers before dispatch,
use supported settings literally and surface unsupported choices. An omitted
effort requests the host default; it does not verify an effective value.
When the package is outside the target cwd, native tool reads of role/protocol
resources may need explicit `--add-dir /absolute/package/path`. A denied read
leaves the assignment pending; continue the same session with authorized access
rather than treating it as consent or task completion.
Native initialization/result captures and a complete temporary-project workflow
are separate live evidence. Loaded metadata and a role name printed by a model
are insufficient. Capture sources/revision, role behavior, requested versus
reported settings, contact, question/continuation and finish authorization.

Sources: [Qoder package fields](https://docs.qoder.com/cli/plugins-reference),
[Qoder hook protocol](https://docs.qoder.com/cli/hooks),
[Codex hook registration and root variables](https://developers.openai.com/plugins/build/plugins#bundled-mcp-servers-and-lifecycle-hooks).

## Remaining harness mappings

These mappings retain the November 18 source/documentation research. They are
integration candidates, not shipped adapters or live certifications. None
permits a substitute preset, inherited model, guessed effort translation,
unverified generic-role equivalence or overlapping replacement writer.

| Harness | Package and role mapping | Executor / handoff limits | Primary sources |
|---|---|---|---|
| Hermes | Shared skill trees through trusted project/profile discovery; native `plugin.yaml` and Python registration; absolute common role/brief paths in isolated delegation | Default child routing is profile-wide. Per-assignment model/effort needs a verified native route or a chosen independent session. Child results/continue exist; peer-root inbox, imports and recovery remain untested. Shell hooks use native lowercase events and argument splitting. | [Skills](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills), [delegation](https://hermes-agent.nousresearch.com/docs/user-guide/features/delegation), [hooks](https://hermes-agent.nousresearch.com/docs/user-guide/features/hooks) |
| OpenCode V2 | Native skill sources and `.opencode/agents`; shared role body registered with `mode: subagent` or `all`; server plugins own hooks | Copying unchanged roles defaults to primary. Explicit `provider/model#variant` binding needs verification; public call overrides/effort and reconnect event replay remain unverified. Continue by returned session ID. V1 differs. | [Agents](https://opencode.ai/docs/agents), [subagent](https://opencode.ai/docs/tools#subagent), [server plugins](https://opencode.ai/docs/build/plugins/server) |
| Gemini CLI | Configure `context.fileName` for AGENTS; native `gemini-extension.json`, skill directories and `.gemini/agents` role bodies | Explicit child model and scoped `thinkingConfig` depend on the selected model/auth route; no generic effort conversion. Child results and headless root resume differ from a live peer inbox. Imports, mounted resources and hook translation remain untested. | [Skills](https://geminicli.com/docs/cli/skills/), [subagents](https://geminicli.com/docs/core/subagents/), [generation](https://geminicli.com/docs/cli/generation-settings/), [hooks](https://geminicli.com/docs/hooks/reference/) |
| Qwen Code | AGENTS, native skills/agents and `qwen-extension.json`; preserve complete resource tree and use regular clean children | Explicit model/auth binding exists; ordinary public per-child effort remains unestablished despite internal support. Native peer delivery does not imply read; ACP refuses inbound peer messages. Agent Plugins v1 covers skills/MCP, not full roles/hooks. | [Skills](https://qwenlm.github.io/qwen-code-docs/en/users/features/skills/), [roles](https://github.com/QwenLM/qwen-code/blob/main/docs/users/features/sub-agents.md), [portable subset](https://qwenlm.github.io/qwen-code-docs/en/users/extension/agent-plugins/), [peers](https://qwenlm.github.io/qwen-code-docs/en/users/features/cross-session-protocol/) |
| Kimi Code CLI | Current native `kimi.plugin.json` / `.kimi-plugin/plugin.json`, `.kimi-code/agents` and shared skills; `--skills-dir` replaces discovery | Foreign role model frontmatter is ignored. Model-pool aliases must implement the explicit project model/default effort, not replace it with a new preset. Precedence, live relay, hooks and complete imports remain untested; old `kimi-cli` is archived. | [Agents](https://www.kimi.com/code/docs/en/kimi-code-cli/customization/agents), [configuration](https://www.kimi.com/code/docs/en/kimi-code-cli/configuration/config-files.html), [tools](https://www.kimi.com/code/docs/en/kimi-code-cli/reference/tools.html), [plugins](https://www.kimi.com/code/docs/en/kimi-code-cli/customization/plugins.html) |
| GLM via named host / ZCode | GLM/Z.ai routes retain the actual host contract. ZCode has native plugin/Markdown role registration with Claude fallback, native hooks and `ZCODE_PLUGIN_ROOT` | ZCode explicit `model` + `thoughtLevel` differs from `reasoningEffort`; inheritance changes effort behavior. CLI/headless/root resume, automatic shared discovery and per-child isolation remain unestablished. Ordinary timed questions never imply consent. | [Named host route](https://docs.z.ai/devpack/tool/opencode), [roles](https://zcode.z.ai/en/docs/subagents), [plugins](https://zcode.z.ai/en/docs/plugin), [hooks](https://zcode.z.ai/en/docs/hooks) |

Use each host's native install/update mechanism and verify its actual version,
loaded package paths/revision and role priority before adopting it. Research
cannot establish hidden server routing. Pi is excluded. The accepted policy is
recorded in [provider-independence.md](../docs/provider-independence.md).
