# Provider independence: research and decisions

Updated: 2026-11-19. Research baseline: `2813cee`.

This is the working record of the dependency-by-dependency discussion: evidence,
corrections, alternatives and accepted decisions. It is not a build plan or a
claim of live compatibility. Dependencies 1, 2, 4, 5, 6 and 7 have accepted decisions below;
dependency 3 is conditional on preserving role identity. Pi is excluded at the
user's request.

## Scope and existing constraints

Keep the shared stages: planning, build and acceptance. Primary and secondary
remain executor presets. Grill is an interview; run approval precedes approval
of a linked summary of at most 350 words. Planning then stops until the user
chooses where build starts. The user or designated orchestrator directs the
same build writer within granted authority.

The earlier portability run removed fixed role models and the engine allowlist.
That makes names configurable; it does not prove that every host can apply the
same model identifier, effort, child-session or messaging operation.

## Research trail

### 1. Start with concrete repository dependencies

The initial search found a Claude-only hook launcher, `.claude/skills` paths,
host-specific tool guidance and model presets in AGENTS. We then checked the
behavior behind those names rather than treating every vendor mention as a
runtime dependency.

The important distinction: model names in [AGENTS.md](../AGENTS.md) are intended
configuration. An optional adapter can legitimately describe one host. A shared
workflow that requires an unavailable native tool is an actual execution gap.

### 2. Reproduce the hook-root failure

Both entries in [hooks/hooks.json](../hooks/hooks.json) expand only
`CLAUDE_PLUGIN_ROOT`. A secondary worker ran the declared command in a temporary
mirror with one plugin-root variable at a time. The Claude control passed. With
only `QODER_PLUGIN_ROOT`, Python exited 2 trying to open `/hooks/advise.py`.

The existing hook tests call the Python handler directly, so they did not cover
this launcher failure. The worker retained a red test patch locally as
`.ai-workflow/plans/2026-11-18-qoder-portability.red.patch`; source files were
left unchanged.

This minimal reproducer reads the actual declared command. Run from the
repository root; it needs no installed Qoder:

```sh
python3 - <<'PY'
import json, os, subprocess
from pathlib import Path

hooks = json.loads(Path("hooks/hooks.json").read_text())
command = hooks["hooks"]["PostToolUse"][0]["hooks"][0]["command"]
env = os.environ.copy()
env.pop("CLAUDE_PLUGIN_ROOT", None)
env["QODER_PLUGIN_ROOT"] = str(Path.cwd())
result = subprocess.run(command, shell=True, env=env, input="{}",
                        text=True, capture_output=True)
print("exit:", result.returncode)
print(result.stderr)
PY
```

[Qoder's hook reference](https://docs.qoder.com/cli/hooks) documents its root
variable and shell expansion. This is evidence about the launcher, not proof
that agent dispatch or plugin discovery fails.

### 3. Correct the manifest hypothesis

We initially treated the missing `.qoder-plugin/plugin.json` as a loading
blocker. The [official plugin reference](https://docs.qoder.com/cli/plugins-reference)
makes that manifest optional for conventional directory discovery. We discarded
the missing-file assertion as proof of a runtime defect. Marketplace requirements
and actual installed-version behavior still need their own verification.

### 4. Compare host contracts using secondary researchers

The research covered Claude Code, Codex, Qoder CLI, Hermes, OpenCode, Gemini CLI,
Qwen Code, Kimi Code and GLM through a named host, including ZCode. Pi research
was stopped and excluded when the user requested it.

The comparisons checked instruction/skill discovery, role registration, clean
worker contexts, model and effort selection, result/question delivery,
continuation, worktrees, permissions, hooks and packaging. Official docs and
source were used; missing documentation was recorded as uncertainty, not as
proof of missing functionality.

Three findings widened the investigation:

- Host, API connection, model ID and effort are distinct. The current
  provider-keyed pair alone does not describe every host's native namespace.
- A shared role prompt is portable; its native registration and dispatch tool
  are not necessarily interchangeable.
- [scripts/check](../scripts/check) requires Claude and Codex. The test harness
  invokes it, so contributor checks retain a separate vendor dependency.

The open [Agent Skills format](https://agentskills.io/specification) supplies
shared skill content, not a universal delegation or lifecycle protocol.

### 5. Refine the question about hook availability

The issue is not simply whether a product advertises hooks. Supported events,
registration, input/output, trust and execution scope differ. For example,
[OpenCode uses plugin APIs](https://opencode.ai/docs/build/plugins/server),
[Hermes has several hook systems](https://hermes-agent.nousresearch.com/docs/user-guide/features/hooks),
and [Qwen's portable plugin format](https://qwenlm.github.io/qwen-code-docs/en/users/extension/agent-plugins/)
ignores hooks even though the host has a native hook mechanism.

Thus documented hook support does not establish compatibility with our JSON
declaration, Python payload handling or startup/compaction expectations.

### 6. Inspect Superpowers as an existing solution

Verified canonical project: `obra/superpowers`, version 7.0.2, revision
[`22f0b463e7a5e579904dd6211a520321035526f7`](https://github.com/obra/superpowers/commit/22f0b463e7a5e579904dd6211a520321035526f7).
The old local November 15 snapshot was not used as current evidence.

| Inspected source | Finding |
|---|---|
| [Codex manifest](https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/.codex-plugin/plugin.json#L23) | Exposes the shared skills and explicitly sets `hooks: {}`. |
| [Claude hook declaration](https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/hooks/hooks.json) | Still uses `CLAUDE_PLUGIN_ROOT`; it is not a universal launcher. |
| [Session-start handler](https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/hooks/session-start) | Resolves content relative to itself and selects a host-specific output envelope. |
| [Hermes adapter](https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/.hermes-plugin/__init__.py) | Registers the same skill files and injects bootstrap through first-turn `pre_llm_call`, excluding children. |
| [OpenCode adapter](https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/.opencode/plugins/superpowers.js) | Registers shared skills, maps tools/names, handles lifecycle differences and skips controller bootstrap in children. |

The reusable pattern is shared behavior plus host-specific connection code.
It does not eliminate native contracts. Superpowers also permits inline work
when delegation is unavailable in some mappings; that fallback is not adopted
here because our coordinator/worker boundaries remain a separate requirement.

## Decision 1: optional host hooks — accepted

The user accepted the following boundary after reviewing the Superpowers
comparison:

1. Common skills and mandatory CLI checks work without hooks.
2. One common advisory handler supplies our reminders.
3. Optional host adapters handle event registration, handler location and
   input/output conversion.
4. Without a usable hook integration, skills explicitly invoke the necessary
   CLI checks; no workflow stage is skipped.
5. Hooks do not grant approval or replace the CLI's acceptance safeguards.

This preserves [hooks#advise-only](spec/hooks.md) and the existing
[executor/handoff contract](../references/SESSIONS.md).

Considered alternatives:

- **One shared launcher listing every host's environment variables:** handles
  particular paths but leaves event/payload differences and a growing host list
  in the common integration.
- **Remove all hooks:** removes integration work but loses useful automatic
  reminders on hosts that support them.
- **Copy Superpowers wholesale:** unnecessary for this boundary and would bring
  workflow/fallback choices that have not been agreed here.

Adapter locations, installation commands and the exact neutral handler protocol
are not selected yet. This decision does not authorize implementation or a build.

## Decision 2: project-local instructions and presets — accepted

The package's `skills/` tree is the common content source. A host can discover
that content through its own installation, registry, configured directory or
links. Separate native installations need not mean separate versions of the
workflow prose. The [Agent Skills integration guide](https://agentskills.io/client-implementation/adding-skills-support)
describes `.agents/skills/` as a sharing convention; the format itself does not
mandate discovery directories.

Shared project rules remain in AGENTS.md, skill content stays
in SKILL.md and relative resources, and host adapters expose those files through
native discovery. Shared skill instructions should use the available catalogue
and supplied paths rather than maintain a growing list of host directories.
A host-specific instructions file can import the common rules without becoming
another independently maintained workflow. Exact native registration and
packaging remain dependencies 3 and 6.

### Research: the CLI and the host do not load AGENTS identically

Inspection of `agents_executors()` in [pipeline.py](../skills/build/pipeline.py)
showed that it reads a literal Executors block in root AGENTS.md. It does not
implement a host's imports or instruction precedence.

A secondary worker tested identical valid profiles in one temporary Git repo:

```text
Root AGENTS.md: @docs/executors.md
executor show: exit 1, executors-missing

Root AGENTS.md: literal ## Executors TOML block
executor show: exit 0, expected Probe primary/secondary profiles
```

No host was launched. This proves the CLI-side limit only. A host with file
imports could read the referenced instructions while the CLI still rejects the
configuration. The temporary repository was removed; source files were untouched.

The user selected profiles in **each project's root AGENTS.md**, filled for the
intended harness. A brief manual setup per project is an acceptable cost.
The CLI reads the literal Executors block there; it does not need an external
shared profile file or emulation of native import/search hierarchies. Prose
instructions can still reference other files without moving the machine-read
configuration. Model namespaces and effort semantics remain dependency 4.

The rejected alternative was one shared external profile file for multiple
projects. Keeping project-local configuration makes the reviewed source explicit
and retains the current parser contract without another lookup mechanism.

## Dependency 3: shared roles versus native registration — under discussion

The current build skill asks for named `dev-skills:implementer` and
`dev-skills:judge` agents. A role's behavior can remain in the shared Markdown
file even when a host does not register that native type.

A secondary researcher verified a concrete existing example: Superpowers'
[pinned Kimi adapter](https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/.kimi-plugin/plugin.json#L27)
maps implementation and code/spec/quality review to the native `coder` child,
passing the filled task prompt. Separate behavioral roles are not registered.
Codex can similarly receive role and brief paths in a fresh worker prompt.
[OpenCode's built-in general child](https://opencode.ai/docs/agents) can receive
the role instructions, although explicit model/variant routing may require
native metadata. That binding remains dependency 4.

Proposed boundary: maintain one set of role instructions and dispatch a fresh
worker with the role, brief and selected preset. Native registration is a thin
optional mapping when needed, not a second implementation of the role.
The required role and brief must be readable; silent omission is not a valid
fallback. If isolated execution or preset application is unavailable, surface
the limitation rather than moving execution into the coordinator's context.

### Required condition: preserve role identity

Further source research showed why generic dispatch is conditional:
[OpenCode custom-role instructions](https://opencode.ai/docs/agents#system)
can occupy the system-prompt slot, while a task asking a general child to read
a role file does not automatically have the same priority. Superpowers' Kimi
mapping proves reuse, not equivalent enforcement of role restrictions. No live
equivalence test has been performed.

The user accepts this direction only if it preserves the existing approach:
every worker must retain who it is. A generic host label such as `coder` or
`general` is a dispatch mechanism, not the worker's workflow role.

- Keep one authoritative instruction body for implementer, reviewer and judge.
  Use native custom-role instructions where already supported; there is no
  requirement to replace working registrations with generic agents.
- Bind each worker to its explicit role, brief, territory or review range,
  executor preset, working directory, controller and reporting obligations before
  work begins. Primary/secondary choose executor caliber; they do not define or
  change role identity.
- Preserve that binding on continuation and context recovery. A resumed worker
  must recover its role and current brief, not depend on remembering the first
  task message. Never reuse an implementer's context as the independent reviewer
  or judge.
- A generic child is acceptable only where the host can apply and preserve the
  same role instructions without conflicting higher-priority native behavior.
  Otherwise provide native registration or report that the mode is unavailable.
  Do not silently weaken role restrictions or execute inline in the coordinator.

Before adopting an adapter, verify the dispatched role source and initialization,
continuation behavior, task boundaries and result/report contract on that host.
A worker merely printing its role name is diagnostic information, not proof of
equivalent behavior or a permission boundary. No role adapter is certified by
this discussion alone.

For optional OpenCode registration, [file substitution](https://opencode.ai/docs/config#files)
can reference common content. Missing files expand to empty strings, reinforcing
the need to validate the reference. These are source/documentation findings;
no live role dispatch was performed in this investigation. This dependency's
policy has not yet been accepted.

## Decision 4: explicit project executor settings — accepted

The user chose explicit settings in each project's AGENTS.md, even when a harness
supports named native presets. The project lists primary and secondary model
settings by provider, filled for the intended harness. At run creation all
configured provider pairs are copied; the active provider and workflow role
select the applicable pair from the approved snapshot. Provider names remain
open configuration keys, not an allowlist or a way to infer authentication.

The November 18 host research established different binding mechanisms:
[OpenCode selects model variants](https://opencode.ai/docs/agents#model),
[Hermes delegation can use explicit routing](https://hermes-agent.nousresearch.com/docs/user-guide/features/delegation#delegation-strategies-delegationbackend),
and [Kimi can bind model-pool aliases and efforts](https://www.kimi.com/code/docs/en/kimi-code-cli/configuration/config-files.html).
These are candidate native mechanisms, not live-certified adapters. Runtime
internal support for a setting is not proof the public child-dispatch tool
exposes it.

Accepted policy:

- Keep primary/secondary as workflow presets and their assignments unchanged.
- The project owner supplies an explicit model identifier and, when applicable,
  effort for the selected harness. A native model alias can identify a model;
  it is not permission to replace the pair with an external execution preset.
  Shared skills do not equate similarly named effort levels or maintain
  model-vendor catalogues.
- A host adapter applies the approved model/effort pair through a supported
  interface. Native routing machinery may be needed internally, but it must
  implement the project/run values rather than become another source of truth.
  It must not silently inherit another preset, drop an unsupported setting or
  substitute a model. If it cannot apply the pair, surface that limitation.
- Keep credentials and connection authentication in the harness configuration;
  do not copy secrets into the project or run snapshot.
- Snapshot the approved choices in the run. Report effective settings where the
  runtime exposes them, and distinguish those observations from requested aliases.
  Unknown server-side routing cannot be certified merely from an alias string.

Follow-up schema review distinguished native model aliases from routing presets
selected through a different host parameter. We considered adding a native-preset
reference as an alternative to model/effort. The user rejected that alternative:
the explicit project configuration remains the source even if configuring it
for a harness takes a small manual step. No `profile`/`preset` alternative or
freeform settings map is selected.

Names and supported parameters can still differ between harnesses using the same
model vendor. That is a binding/validation concern: do not silently translate
levels or reinterpret an approved choice. Changed project settings do not alter
an already approved run; a changed run requires its existing approval flow.
Reported runtime selection, when available, remains distinct from requested
configuration and does not certify hidden provider routing.

No universal effort translator, credential manager or runtime launcher is
selected. Explicit configuration cannot create a per-child setting capability
missing from the host's public interface.

## Decision 5: artifact-backed questions and continuation — accepted

The current shared instructions require native messages for worker questions
and continuation. Host research distinguishes a child tool's final result from
an arbitrary peer-session inbox. For example, [Qoder peer messaging](https://docs.qoder.com/cli/cross-session-messaging)
has separate opt-in/platform conditions, while [Gemini's child agents](https://geminicli.com/docs/core/subagents/)
return findings without establishing a universal live-peer messenger. These
are different contracts, not alternative spellings of one required tool.

The earlier live Herdr build also supplied a practical counterexample: a prompt
reported stalled while subsequent inspection showed the worker was working.
Settled states were observed between child waits without the build being done.
Thus a timeout is not proof of non-delivery, and idle is not proof of phase
completion or acceptance. The existing one-writer and inspect-before-resend
requirements remain necessary regardless of transport.

Accepted common protocol:

- Use supported native messages and continuation when available.
- Otherwise return an actionable question, blocker or final result through the
  host's result channel or an agreed report artifact. The coordinator must
  actually collect it. Ending a turn with a question does not complete a phase.
- The coordinator answers within existing authority, obtains missing user
  decisions through the designated contact, and records decisions/phase changes
  through the existing CLI. Workers keep their own prescribed report commands;
  the coordinator does not create duplicate copies of those reports.
- Preserve role, phase, brief, approved executor, working tree, return contact
  and current progress when continuing. Message delivery and permission prompts
  never imply workflow approval.

The user accepted explicit replacement when native continuation is unavailable,
using the artifact-backed Superpowers pattern. Replacement is allowed only after the previous
worker and its write-capable background work are confirmed quiescent. An
unreachable or timed-out attempt is unknown, not stopped. Give the replacement
the same role and an updated brief with
verified repository/CLI progress and the unresolved question/answer. It resumes
the work from facts, not by replaying the phase's commands, and does not become
an independent pipeline writer. Keep the coordinator out of implementation and
never reuse an implementer's context as reviewer or judge.

A narrow code audit found a concrete boundary: phase start rejects duplicate
starts, and phase done validates reports, commits, territory and cleanliness,
but the state file lock does not authenticate a worker or attempt. A phase
report can overwrite the running phase's report; fix/round reports target the
current assignment. A delayed old worker could still commit or report.
Therefore replacement requires an operational handoff with no old writer left;
current CLI locking alone does not establish that guarantee. Continue the
existing assignment rather than calling phase start again. Carry existing
findings/results into review/E2E recovery to prevent duplicate recording.

Product answers and host permission dialogs remain separate: neither is
authority for the other, and neither implies acceptance of the final result.

The rejected alternative was to require native worker continuation for every
supported host. It would reduce adaptation but exclude otherwise usable paths.
The accepted fallback does not permit starting another worker after an ambiguous timeout or
pretending that a replacement is the original session. No new message broker,
queue service or workflow engine is needed.

### Superpowers follow-up: recovery through artifacts

Checked again on 2026-11-19; main still resolved to revision
`22f0b463e7a5e579904dd6211a520321035526f7` (7.0.2).

- The [implementer template](https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/subagent-driven-development/implementer-prompt.md)
  requires a persistent full report and a short returned status: DONE,
  DONE_WITH_CONCERNS, BLOCKED or NEEDS_CONTEXT. Blocker/question details belong
  in the returned message so the controller can act without a separate inbox.
- [Report handling](https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/subagent-driven-development/references/handling-reports.md)
  supplies missing context and re-dispatches; a blocked attempt requires a
  changed input or approach rather than an identical blind retry.
- The [fix-loop instructions](https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/subagent-driven-development/references/fix-loop.md)
  prefer the original implementer, but explicitly allow a fresh implementer
  when the harness cannot message it. The replacement receives the brief path,
  existing report path and findings; fix reports append to that report. Later
  escalation can also use a fresh stronger worker. Model escalation is not
  automatically adopted here: our approved executor assignments still apply.
- [Resumption](https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/subagent-driven-development/references/resuming.md)
  checks the ledger's plan identity, skips completed tasks and continues an
  unfinished fix loop. Their shared progress ledger and Git history preserve
  progress across controller compaction. Our existing CLI records, reports and
  commits can serve that purpose without a second independently edited ledger.

In this mode [Superpowers dispatches implementers sequentially](https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/skills/subagent-driven-development/SKILL.md#L208).
That reduces conflicting work, but is not technical proof that an old process
cannot write. The inspected instructions and helpers do not establish worker
attempt ownership or revoke an old worker's reporting ability. We must retain
our explicit quiescence check rather than crediting it to Superpowers.

Its separate inline fallback is also not adopted: the agreed coordinator/worker
separation remains. The reusable finding is artifact-backed continuation or
same-role replacement, not a new transport service or weaker execution mode.
No live Superpowers session was run. The user accepted the recovery pattern
with our additional old-writer quiescence and role-identity requirements.

## Decision 6: shared package and native installation — accepted

The current repository already shares skills, role prompts, references and CLI
between its Claude and Codex metadata. A narrow packaging review confirmed that
the complete layout matters: skills invoke the sibling pipeline CLI and read
root references/roles. Installing only individual SKILL.md files is insufficient.
Interpreter calls and required file permissions must survive distribution.

Superpowers explicitly uses separate native installations from one repository:
[installation contract](https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/README.md#installation).
Its [OpenCode installation guidance](https://github.com/obra/superpowers/blob/22f0b463e7a5e579904dd6211a520321035526f7/.opencode/INSTALL.md)
also distinguishes host versions and stale dependency caches. An installed
version label alone is not proof of which source revision was loaded; our
research baseline still carries version 5.1.3 after unreleased code changes.

Accepted boundary:

- One repository/release and synchronized versioned metadata, with common skills,
  role bodies, references and CLI.
- Thin host-specific manifests/bootstrap/adapters point to that common content;
  provider models do not require a separate plugin package.
- Use each host's native installation/update mechanism. Do not introduce a
  universal installer, automatic host detection or global credential setup.
- Preserve the full resource layout and distinguish installed package code from
  the target project's AGENTS profiles, worktree and workflow artifacts.
- Verify loaded paths/revision and the existing root-versus-worker bootstrap
  rules. Installation success establishes discovery, not equivalent execution.

The [Agent Plugins v1 specification](https://agent-plugins.org/specification)
standardizes skills/MCP, not all native role/hook functionality. Another portable
manifest is not selected merely because a standard exists; add metadata only
when the chosen integration requires it. No package format removes the need
for host/version acceptance checks. The user accepted the shared-package/native-
installation approach; certification requirements are dependency 7. Pi remains
excluded.

## Decision 7: provider-neutral shared scripts — accepted

The source audit distinguishes named host examples in fixture data from actual
installed-client dependencies. `scripts/check` directly invokes Claude's
validator and a real temporary Codex installation/prompt inspection. Further,
`test/cli/harness.test.sh` invokes `scripts/check`, bringing that dependency into
the default test suite despite the runner's standard-library-only comment.
By contrast, `test/cli/check-codex.test.sh` already tests its adapter with a stub
executable and needs no real Codex installation or model call.

A secondary worker verified this in a temporary subprocess PATH containing
Python and the necessary shell utilities but neither AI client:

```text
scripts/check-links.py          exit 0, all six categories have no findings
scripts/check                  exit 1, Claude and Codex unavailable
test/cli/check-codex.test.sh     exit 0, executable stub only
```

The full suite was not run in this probe; its real-client dependency was traced
through the harness call. The global environment, source and installed clients
were not changed. This separates actual executable dependencies from harmless
vendor names in synthetic fixtures.

The user accepted removing provider hardcoding from scripts. This applies to
shared entrypoints, not only the mandatory client calls in checks. Format and
command knowledge that genuinely differs by host belongs in optional host
adapters, rather than a closed provider catalogue in common script logic.

Accepted contract:

- The default core checks and unit/fixture tests require the documented shared
  runtime, not installed AI clients. Keep reference/frontmatter/budget checks,
  CLI lifecycle regressions and offline adapter-contract tests there.
- Native installation/loading and live execution checks are separately selected
  for named hosts and versions. A fixture pass is not a real host pass, and a
  loader pass is not a complete role/model/handoff certification.
- Report what ran. Core PASS does not imply all hosts passed. A selected required
  integration that cannot execute is a failure/unperformed requirement, never a
  silent pass. Nonselected integrations are outside that run's coverage.
- Changes to a host adapter require that host's relevant checks in the plan/run;
  unrelated core work need not install every supported client.

This changes the scope promised by the common check command, not the truthfulness
rule that unavailable verification cannot count as passed. It does not require
a new test registry, automatic installer or model-call framework. Existing Bash,
Python 3.11+, Git and POSIX locking requirements are platform dependencies, not
model-provider requirements. Their cross-platform expansion is not selected here.

The all-scripts follow-up also found a genuine shared-interface catalogue in
`scripts/usage`: fixed Claude/Codex source choices, an implicit Claude default,
host-specific default transcript roots and a parser branch. These describe
transcript formats, not inference providers. Removing that common catalogue
must preserve existing readers and their error/token/accounting behavior behind
explicit format adapters; merely adding more host names would repeat the lock.
It does not require inventing readers for formats not yet investigated.

`pipeline.py` already accepts open provider/engine identifiers; its generic
validation should stay. Browser CDP behavior is unrelated to model providers.
Vendor names in fixtures and intentionally host-specific adapters are not
themselves common-script dispatch dependencies.

Exact command names, adapter discovery and compatibility details remain
implementation decisions to make concrete in the plan. No validation, usage or
hook code has changed during this discussion.

## Remaining dependency agenda

| Dependency | Current question | Status |
|---|---|---|
| 1. Hooks | Keep the common process independent of optional host hooks | Accepted above |
| 2. Instructions and skill discovery | Shared content; presets physically in each project's root AGENTS.md | Accepted above |
| 3. Role registration | Shared prompts/native registration with stable role identity | Conditional; identity preservation required |
| 4. Executor binding | Explicit project model/effort pairs by provider, copied into approved runs | Accepted above |
| 5. Worker protocol | Artifact-backed continuation/replacement with role identity and no old writer | Accepted above |
| 6. Packaging | One shared package with thin native adapters and native installs | Accepted above |
| 7. Repository checks/scripts | Portable defaults; explicit host adapters instead of closed catalogues | Accepted above |

Dependencies 1, 2, 4, 5, 6 and 7 have been accepted. Dependency 3 requires preserved role
identity and host verification. Names in examples are not
automatically dependencies; optional adapters are not universal compatibility
guarantees.

## Evidence limits

The hook-root failure was reproduced locally. The wider host and Superpowers
comparisons are documentation/source research, not live end-to-end certification.
No installation, account configuration or implementation changes were made for
this investigation. The user's separate Qoder installation is not treated as a
passing runtime test.

Detailed secondary-worker notes are retained locally under the git-ignored
`.ai-workflow/research/2026-11-18-provider-independence/`. This document preserves
the reasoning, corrections, accepted boundary and primary sources independently
of those disposable local notes.
