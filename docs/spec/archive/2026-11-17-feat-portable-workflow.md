This is history; the rules that hold now are in `docs/spec/`.

# Plan: Make dev-skills provider-neutral with explicit approvals

## Result

Skills currently assume Claude models, herdr and an original-session controller; compilation grants approval and status writes bypass required stages. Planning will interview, obtain run approval, present a summary for approval, then stop. Build and acceptance will use provider presets and CLI-verified evidence under the user's chosen controller.

## Approach

- `AGENTS.md` is the shared instructions source. Its Executors section defines each provider's primary/secondary model and optional effort. Before run approval, select the current provider's AGENTS presets; afterward use the frozen run snapshot of every configured provider. Provider, model and effort names remain opaque values.
- Primary covers planning, build coordination, initial review and judgment. Secondary covers helpers, prototypes, implementation, E2E and rechecks. Apply assignments explicitly; inheriting an omitted model is insufficient.
- Separate validation from consent. Record approval of the proposed run, then approval of a summary bound to that run and the plan's planning content, including Spec. State rendering must not invalidate consent; changed approved content must.
- Grill is an interview. Summary approval stops planning; only a separate instruction selects herdr, a native independent session or manual handoff. Acceptance follows the user or designated orchestrator's granted authority, with one state writer and unchanged relayed words.
- Enforce mandatory evidence, including at direct status writes and finish. Preserve reasoned judge dispositions, stopped-round handling and the existing explicit land-hook exception; display their consequences on the current page.
- Carry the already-authored glossary and resume-example changes into the isolated build. Preserve unrelated checkout edits. The current run was approved in this conversation; do not ask its settings again or fabricate historical approvals.

## Out of scope

- SDLC Factory, a launcher framework, new host integrations or transcript parsers, and release publishing.
- Existing whiteboard changes under `docs/pipeline*` and their tests.

## Done and Spec

```text
## Done

1. Dispatch grill helpers using current AGENTS Executors profiles, then draft a run for GPT, Qwen, Claude and another provider → all profiles are copied; malformed presets and unknown fixed fields identify their paths; model names have no vendor allowlist.
2. Approve a run, change AGENTS, then transfer planning from GPT to a Claude build → approved profiles stay frozen and Claude selects its own pair; missing profiles produce an actionable request.
3. Validate a draft before consent → no approval; approve run then the current summary → build becomes eligible. Change run, plan or Spec → affected consent is stale; progress records survive reapproval.
4. Follow planning through grill and the approved resume example → interview has no approval gate; the summary links the plan, explains phases, Spec, checks and limits within 350 words; approval alone starts nothing — you check.
5. Start build by explicit herdr/native/manual instruction; review directly and through a designated orchestrator → the chosen contact controls acceptance within granted authority; resume reuses the existing writer and relayed words stay unchanged — you check.
6. Record first verdicts with `--engine qwen`, `pi` and `hermes` → names reach the judge header; empty/multiline identifiers and missing prediction are refused; later-verdict rules remain intact.
7. Attempt passed, request-link or merged shortcuts without required current judge, land, page or acceptance records → refused without state or target changes; supported request-link recording still works after a valid finish flow.
8. Complete phases, gate, judge, land, page and authorized acceptance, including a feedback round → ff-only finish uses the agreed ending and retains backups; existing judge dispositions and explicit land-hook exceptions remain visible and supported.
9. Change the branch tree or approved planning content after a page/acceptance → stale stages are identified; passed and finish refuse until the required evidence and acceptance are current.
10. Read a completed old run and adopt an unfinished one → completed history is unchanged; unfinished progress survives, but missing new approvals are not inferred at protected transitions.
11. Read every core skill, role and generated brief → shared rules come from AGENTS; planning, build coordination, first review and judge use primary; helpers, code, E2E and rechecks use secondary; no fixed provider/model or herdr-only requirement remains.

## Spec

+ planning — Planning
  About: Interviewing, configuring a run and approving its execution summary.
+ planning#summary-before-build — Planning interviews, approves the run, then requests approval of a linked summary of at most 350 words and stops
  Why: the user reviews a concrete result without having to read raw planning files
  Done: 3, 4, 5
~ run#starts-from-last — A new run copies the latest run or the example, strips example credentials and snapshots all current AGENTS Executors profiles
  Why: useful defaults are proposals while provider defaults come from one shared source
  Done: 1, 2
~ run#contract-checked — Fixed run fields and provider presets are validated; task values remain scalar and provider identifiers remain open
  Why: malformed configuration fails without restricting supported providers
  Done: 1, 2
~ run#required-to-approve — Build requires explicit approval of the proposed run and a summary matching the current plan and Spec
  Why: successful validation does not establish consent
  Done: 3
~ run#changes-through-approve — Readers use approved run snapshots; changed approved planning content requires renewed corresponding approval
  Why: configuration cannot silently widen authority or change reviewed behavior
  Done: 2, 3, 9
+ run#executor-presets — The current provider selects primary/secondary from AGENTS before run approval and from the approved snapshot afterward
  Why: role caliber stays stable across providers and session transfers
  Done: 1, 2, 11
~ build#state-through-commands — CLI writes reject rendered drift and missing or stale prerequisites, including direct status changes
  Why: a status cannot replace evidence or approval
  Done: 3, 7, 9
~ build#act-with-a-reason — Recorded operational overrides preserve judgment but cannot manufacture missing approval, judge, land or page stages
  Why: discretion does not authorize skipping the workflow
  Done: 7, 8
~ build#pre-5-1-adopted — Adopting a plan preserves progress without inferring run, summary or acceptance approvals
  Why: historical progress is evidence rather than new authority
  Done: 10
~ build#judge-after-every-round — Every round ends with a primary judge before land and acceptance
  Why: judgment uses the approved provider preset
  Done: 8, 11
~ build#judge-file-by-code — Code writes the first judge file once with HEAD, UTC time and a supplied nonblank single-line engine identifier
  Why: provenance describes the executor without restricting providers
  Done: 6
- build#separate-build-session
  Why: the user separately chooses where build starts after summary approval
+ build#start-chosen — Summary approval starts nothing; a separate instruction chooses herdr, native independent session or manual handoff
  Why: planning does not choose a session topology
  Done: 4, 5
- build#gate-through-original-session
  Why: the original planning conversation is not intrinsically the acceptance contact
- build#feedback-through-original-session
  Why: routing follows the designated controller while preserving one writer
+ build#acceptance-contact — Questions and acceptance go to the user or designated orchestrator within granted authority, with unchanged relayed words and one writer
  Why: responsibility rather than conversation identity controls a run
  Done: 5
~ build#page-from-records — The acceptance page describes current land and records, identifies evidence differences and binds acceptance to that result
  Why: acceptance must describe the result being finished
  Done: 7, 8, 9
~ finish#merge-needs-land — Finish independently verifies current judge, land, page and authorized acceptance before merging, pushing or opening a request
  Why: a passed status alone cannot authorize an unreviewed result
  Done: 7, 8, 9
~ finish#by-run-file — Finish uses the approved run ending after current authorized acceptance, without asking the ending again
  Why: configuration is agreed during planning and execution requires current acceptance
  Done: 8
```
