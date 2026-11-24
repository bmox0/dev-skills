# Executors and build handoff

`AGENTS.md` supplies shared rules. Provider/model identifiers are open. Hooks
are optional advice and confer no approval. Always run prescribed CLI checks.

## Select executors

`CLI` is `python3 "<build skill directory>/pipeline.py"`.
Before run approval, `CLI executor show --provider <provider>` reads literal
project-root AGENTS Executors pairs; add `<plan>` afterward for the frozen
snapshot. Missing profiles require user-supplied, approved choices.

Planning, coordination, first review (including small gates) and judges use
primary. Helpers, prototypes, implementation, fixes, verify/E2E, rechecks and
round reviews use secondary. Explicitly dispatch the selected model/effort;
absent effort uses the provider default. Surface unsupported settings before
dispatch; never inherit, substitute or translate a preset.

## Bind workers

Generate `CLI brief <role> --provider <provider> <plan> …`. Follow
`adapters/<host>/workers.md` when present. Bind assignment/report tools.
Prefer native custom-role instructions. For generic workers, verify equivalent
role priority and behavior and no conflicting higher-priority instructions, or
report unavailable. Coordinators never implement or reuse implementers as
independent reviewers or judges.

Give each clean context its authoritative role source, absolute brief/protocol
paths, assignment/territory or range, approved executor, cwd, return channel and
report commands. Initialization evidence records loaded sources,
requested/effective settings when exposed, cwd/branch and boundaries. Report
missing tools or conflicts before acting. Workers never dispatch. Independent
ready phases may run concurrently within available slots.

Use native messages and continuation when available. Otherwise return actionable
questions, errors or results via the host's result channel or agreed
report artifact. The coordinator collects them and answers within existing
authority. Questions leave work pending. Workers retain report commands.
Coordinators record decisions/transitions without duplicate reports.

## Start and recover once

Planning obtains explicit run approval, then a linked summary approval
(≤350 words), and stops. Summary approval launches nothing. A subsequent
instruction chooses **herdr**, a **native independent session**, or **manual handoff**.
Record absolute plan/run/build-skill paths, tree, provider/primary pair,
session identifiers, contact/channel and acceptance authority beside the plan.
Carry the user's opening language or the approved summary path.
On resume recover it from the handoff or summary. Use it for user messages.
Tracked documents and examples follow comparable project documents' language.
The coordinator owns phase/build/gate transitions; workers retain prescribed
reporting, verdict and land commands. A controller only relays unless granted
acceptance authority; it cannot approve its own result.

On resume run `CLI status --current` to find plans and `CLI status <plan>`
for the owner and next action. Inspect the existing writer, reports and Git
facts before resending. Timeout, idle, delivery and prompts imply no completion
or approval.
Retain role, brief, assignment, executor, tree, contact, reporting and pending
questions/answers. Resume without repeating `phase start` or completed work.

When continuation is unavailable, replace only after the old attempt and all
write-capable jobs are confirmed stopped. An unreachable or unknown attempt
blocks replacement; CLI locks do not stop delayed reports/commits. Report an
exit before restart. Give the same role an updated brief with verified progress,
existing reports and pending answers, then resume the existing assignment.

## Conditional herdr mechanics

Only for herdr, read its installed skill and `herdr --skill`.

```sh
herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" --label "Build" --no-focus
```

Record returned tab/pane IDs and agent name. Launch with the explicit primary
pair and absolute brief. After settled waits inspect `herdr agent get` and
`herdr agent read`; idle alone establishes no gate. Other topologies retain
the same contract through native identifiers/channels.

## Questions and acceptance

Answer routine questions from existing authorization and surface other questions
and permission prompts to the contact. At the human gate relay the validated
guide verbatim and link the page. Recover it with `CLI page <plan> --show`.
Wait while the contact opens the result. Relay notes, rounds and approval
unchanged to the same inspected writer. Retain incoming words while it works.
Notes alone start no round. Only the user or designated
acceptor within granted authority accepts: `CLI accept <plan> --by <name>
--words "<unchanged approval>"` binds current judge/land/page. Finish as configured
when instructed, reusing authorization. Watch through rounds and finish.
