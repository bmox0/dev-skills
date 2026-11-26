# Executors and build handoff

`AGENTS.md` supplies shared rules and prescribed checks.

## Select executors

`CLI` is `runweld`. `CLI executor show --provider NAME` reads literal profiles
from `.runweld/config.toml`. Add `PLAN` for the frozen snapshot.

Planning, coordination, first review (including small gates) and judges use
primary. Helpers, prototypes, implementation, fixes, verify/E2E, rechecks and
round reviews use secondary. Explicitly dispatch the selected model/effort;
absent effort uses the provider default. Surface unsupported settings before
dispatch; never inherit, substitute or translate a preset.

## Bind workers

Use the brief command from `CLI next --plan <plan>`.
Follow `adapters/<host>/workers.md` when present.
Run the brief’s pinned instruction command for the role (for example
`runweld reviewer --plan PLAN` on the selected release).
Check higher-priority host instructions. Coordinators never implement or reuse
implementers as independent reviewers or judges.

Give each clean context its authoritative role source, absolute brief/protocol
paths, assignment/territory or range, approved executor, cwd, return channel and
report commands. Initialization evidence records loaded sources, settings
requested/effective, cwd/branch and boundaries. Report conflicts before acting.
Workers never dispatch. Independent ready phases may run concurrently.

Use native messages and continuation when available. Otherwise return actionable
questions, errors or results via the host's result channel or agreed
report artifact. The coordinator collects them and answers within existing
authority. Questions leave work pending. Workers retain report commands.
Record transitions without duplicate reports.

## Start and recover once

Planning presents the complete plan and run together with `CLI plan review`
and records one human approval. A separate start instruction chooses **herdr**, a **native independent
session**, or **manual handoff** and authorizes `CLI build start <plan>`.
Use `--provider NAME` for multiple providers. Repeat to see the existing assignment.
Record plan/run/build-skill paths, tree, session IDs, contact/channel and
the human's language beside the plan. Approval records acceptance authority.
Tracked documents and examples follow comparable project documents' language.
The coordinator owns phase/build/gate transitions; workers retain prescribed
reporting, verdict and land commands. A controller only relays unless granted
acceptance authority; it cannot approve its own result.

On resume run `CLI next` to find the task, or `CLI next --plan <plan>` to
select it explicitly. Inspect the existing writer, reports and Git
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

Before dispatch, check the returned IDs from Herdr with the pinned
`CLI handoff herdr <plan> --workspace ID --pane ID`. Use `--agent NAME` for
continuation. Launch with the assigned pair and brief. After waits inspect `herdr agent get` and
`herdr agent read`; idle alone establishes no gate. Other topologies retain
the same contract through native identifiers/channels.

## Questions and acceptance

Answer routine questions from existing authorization and surface other questions
and permission prompts to the contact. At the human gate relay the validated
guide verbatim and link the page. Recover it with `CLI page <plan> --show`.
Wait while the contact opens the result. Relay notes, rounds and approval
unchanged to the same inspected writer. Retain incoming words while it works.
Notes alone start no round. Only the named approver or designated acceptor accepts: `CLI accept <plan> --by <name>
--words "<unchanged approval>"` binds current judge/land/page. Finish as configured
when instructed, reusing authorization. Run finish and read its final result
from the surviving project checkout. Watch through rounds and any pending cleanup.
