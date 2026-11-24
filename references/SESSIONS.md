# Executors and build handoff

Shared rules come from `AGENTS.md`; host files adapt them. Provider/model
identifiers are open; a host implies no executor. Hooks are optional advice:
run prescribed CLI checks with or without hooks; hooks confer no approval.

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

Generate `CLI brief <role> --provider <provider> <plan> …`. Follow the host CLI's
`adapters/<host>/workers.md` when present. Bind tools for the assignment and
its report commands. Prefer native custom-role instructions. A generic worker
requires verified equivalent role priority and behavior without conflicting
higher-priority instructions; otherwise report unavailable. Coordinators never
implement. Never reuse an implementer as independent reviewer or judge.

Give each clean context its authoritative role source, absolute brief/protocol paths,
assignment/territory or range, approved executor, cwd, return channel and
reporting commands. Initialization evidence records loaded sources,
requested/effective settings when exposed, cwd/branch and boundaries. Report
missing tools and instruction conflicts before acting. Workers dispatch nobody.
Independent ready phases may run concurrently within available slots.

Use native messages and continuation when available. Otherwise return an
actionable question, error or result through the host's result channel or an
agreed report artifact; the coordinator must collect it and answer within
existing authority. A returned question leaves work pending. Workers retain
their report commands; the coordinator records decisions/transitions without
duplicate reports.

## Start and recover once

Planning obtains explicit run approval, then a linked summary approval
(≤350 words), and stops. Summary approval launches nothing. A subsequent
instruction chooses **herdr**, a **native independent session**, or **manual handoff**.
Record absolute plan/run/build-skill paths, tree, provider/primary pair,
session identifiers, contact/channel and acceptance authority beside the plan.
The coordinator owns phase/build/gate transitions; workers retain prescribed
reporting, verdict and land commands. A controller only relays unless granted
acceptance authority; it cannot approve its own result.

On resume run `CLI status --current` to find plans and `CLI status <plan>`
for the owner and next action. Inspect the existing writer, reports and Git
facts before resending. Timeout, idle, delivery and prompts imply no completion
or approval.
Preserve role, brief, assignment, executor, tree, contact, reporting and pending
questions and answers. Resume without repeating `phase start` or completed work.

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

Surface questions and permission prompts to the designated contact; answer
routine questions from existing authorization. At the human gate report the
current page, concrete artifact/app location, how to try it, checks and limits;
then wait while the contact opens it. Relay notes, rounds and approval unchanged
to the same inspected writer; retain incoming words while it works. Notes alone
start no round. Only the user or designated
acceptor within granted authority accepts: `CLI accept <plan> --by <name>
--words "<unchanged approval>"` binds current judge/land/page. Finish as configured
when instructed, reusing authorization. Watch through rounds and finish.
