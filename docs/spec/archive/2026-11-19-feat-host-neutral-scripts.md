This is history; the rules that hold now are in `docs/spec/`.

# Plan: Remove host catalogues from shared workflow scripts

## Result

Shared checks, usage reporting and hook handling currently embed Claude/Codex assumptions. The common workflow will run without installed AI clients or a fixed host catalogue. Explicit native adapters supply discovery, validation and format conversion while preserving executor choices, worker roles, approvals and recovery.

## Approach

- Follow `docs/provider-independence.md`, including its research corrections. Keep one complete package and native installation mechanisms. Adopt that authored document into the isolated tree; exclude existing `.gitignore` and whiteboard edits.
- `scripts/check` is portable by default. Repeated `--host NAME` explicitly selects native validators; unsupported names, unavailable required validators and invalid selectors fail clearly. Discover adapters without a common client list or automatic installation.
- `scripts/usage` requires explicit `--source NAME`. Keep existing Claude/Codex readers behind format adapters, including their native root defaults, `(record, messages)` output and exact accounting. Missing source becomes an actionable error; do not guess another format.
- Common advice consumes normalized lifecycle/edit information and returns advice. Optional host adapters translate native registration, paths, payloads and output. Hooks remain fail-open and confer no approval.
- Preserve native custom roles where supported. Every worker receives authoritative role instructions, brief, assignment, approved executor, cwd and return/report obligations. Generic dispatch requires verified equivalence. Resume or replace from existing reports/CLI facts; replace only after the old attempt and its writers stop. No coordinator implementation or second ledger.
- Executors remain explicit project-root AGENTS model/effort pairs, copied by provider into run snapshots. Do not add native-preset references, effort translation or a model registry. Preserve CLI lifecycle safeguards.
- Wire native integration for available Claude, Codex and Qoder. Provide evidence-backed setup/tool mappings and declared gaps for the other researched harnesses; do not claim their untested native behavior is certified.

## Out of scope

- Pi, a universal installer/factory, new telemetry formats, release publication, browser/CDP redesign and native-Windows locking support.
- Installing additional clients, changing account credentials or granting acceptance to the controller. Qoder login is performed by the user.

## Done and Spec

```text
## Done

1. Run default checks and unit/fixture tests without AI clients in PATH → pass without client discovery, installation or model calls.
2. Select Claude/Codex validators and a fixture adapter with another name → selected checks execute without editing the common catalogue; unknown, missing, failed and unsafe selectors refuse; coverage names actual validators/versions.
3. Run existing transcript fixtures through explicit sources → filters, message exports, errors, token/cache accounting and descendants match baseline; omitted/unknown source refuses without guessing or reading another format.
4. Drive normalized advice and native hook fixtures, including Qoder-only plugin root → intended status/edit advice; malformed/unrelated input is quiet; disabled hooks skip no CLI safeguard.
5. Load complete packages from relocated paths → common skills, role sources, references and CLI resolve to the intended revision; target-project profiles/artifacts stay outside package code.
6. Read literal project AGENTS, approve run, then change AGENTS → explicit pairs stay frozen; import-only configuration and unavailable choices fail clearly; no external native-preset alternative appears.
7. Initialize and continue roles with captured instruction sources and bounded behavior checks → identity, executor, scope and reports persist; generic mode requires equivalence, and implementer context never becomes independent review.
8. Remove native messaging → actionable question/error/result reaches the coordinator through the agreed result/artifact channel; no idle state, timeout or permission prompt approves/completes work.
9. Replace an unresumable, confirmed-stopped attempt → the same role uses current reports/Git facts without phase restart, duplicate reports or replay; an unknown/still-writing old attempt blocks replacement.
10. Complete consent → build → gate/judge → land → page → acceptance → configured finish without hooks → existing safeguards, reasoned dispositions, hook exceptions and cleanup remain correct.
11. After login, load the package in real Qoder and dispatch all three roles → capture loaded sources, role identity, requested/reported settings and result delivery; unavailable settings or authentication are not passed — you check.
12. Drive a complete Qoder temporary-repository workflow, including question/recovery and authorized finish → captured evidence meets the same contract; fixtures cannot satisfy this required live case — you check.

## Spec

~ hooks#advise-only — Host hooks are optional advice: they neither block tools nor replace mandatory CLI checks or approval safeguards, and handler failures print nothing and exit 0
  Why: workflow correctness must survive absent or unusable hook integration
  Done: 4, 10
~ hooks#status-at-start — Supported native lifecycle events deliver the CLI's active-plan status through the common advisory handler
  Why: adapters translate delivery while the CLI remains the state source
  Done: 4
~ hooks#edit-names-command — Supported native edit events advise which CLI command changes a compiled plan file; unrelated edits add no advice
  Why: native payloads must preserve the shared state-editing contract
  Done: 4
~ run#executor-presets — Literal project-root AGENTS model/effort pairs select primary/secondary before approval and remain frozen in the approved run
  Why: explicit project choices supersede native execution presets or inferred vendor defaults
  Done: 6, 7
~ build#acceptance-contact — Questions, results and acceptance reach the user or designated orchestrator within authority, with unchanged relays and one coordinator advancing transitions
  Why: communication mechanisms confer no approval or change of responsibility
  Done: 8, 9, 10, 12
+ build#worker-role-bound — Workers preserve authoritative role instructions, assignment, approved executor and reporting obligations through initialization and continuation
  Why: a native dispatch label does not establish role identity
  Done: 7, 11
+ build#replacement-preserves-progress — Replace an unresumable worker only after its attempt and write-capable jobs stop, retaining role and verified progress
  Why: CLI locking cannot prevent delayed old-worker reports or commits
  Done: 8, 9, 12
+ validation — Validation
  About: Portable checks and explicitly selected native-host evidence.
+ validation#portable-default — Default checks and unit/fixture tests require the shared runtime without installed AI clients or a fixed host catalogue
  Why: common validation must not require unrelated clients
  Done: 1
+ validation#selected-host-checks — Native checks run only when selected; missing required verification is named and never passed
  Why: explicit coverage keeps unavailable verification visible
  Done: 2, 11, 12
+ validation#coverage-is-named — Reports distinguish core, fixture, loader and live coverage, actual versions and limits
  Why: narrower evidence cannot certify broader compatibility
  Done: 2, 5, 11, 12
+ usage — Usage reports
  About: Session measurements through explicit transcript-format adapters.
+ usage#format-is-explicit — Format readers and native log roots belong to explicit optional adapters, without a common fixed catalogue or implicit host default
  Why: transcript schemas identify hosts rather than inference providers
  Done: 3
+ usage#measurements-preserved — Existing readers preserve filters, exports, token accounting, descendants and errors
  Why: removing dispatch coupling must not lose or miscount data
  Done: 3
+ distribution — Distribution
  About: One complete shared package exposed through native integration metadata.
+ distribution#shared-resources — Native installations expose the same complete skills, roles, references and CLI from the intended revision
  Why: instructions without their resources do not install the workflow
  Done: 5, 11
```
