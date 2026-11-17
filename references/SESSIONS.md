# Executors and build handoff

Shared project rules come from `AGENTS.md`; host files only import or adapt
those rules. Provider and model identifiers are open; no host implies a model.

## Select executors

Before run approval, `CLI executor show --provider <provider>` reads the
current project's AGENTS Executors profiles. After approval, add `<plan>` to
read that provider's frozen run snapshot. Missing profiles require the user
to supply and approve them; never substitute another provider or inherit a model.
`CLI` is `python3 "<build skill directory>/pipeline.py"`.

Use primary for planning, coordination, the first review (including a
small gate) and every judge. Use secondary for helpers, prototypes,
implementation, fixes, verify/E2E, rechecks and round reviews. Every dispatch
explicitly sets the selected model and effort when present; absent effort uses
the provider default, never an inherited role override. If the host cannot
apply a preset, surface the limitation before dispatch.

Every new brief uses `CLI brief <role> --provider <provider> <plan> …`; its
Executor headers give the assigned tier/model/effort. Hand a clean context
its role file or worker skill and absolute brief path. Role agents report to
the build writer; they dispatch no further agents. Use the host's native
message tool for questions and idle-agent continuation. Ready independent
phases can run concurrently within available slots.

## Start once

Planning compiles, obtains explicit run approval, then approval of a linked
summary of at most 350 words, and stops. Summary approval launches nothing.
A subsequent instruction chooses **herdr**, a **native independent session**,
or **manual handoff**; there is no required host or topology.

Record the choice, absolute plan/run/local build skill paths, working tree,
provider, selected primary preset, designated contact and their acceptance
authority beside the plan. The contact is the user or their designated
orchestrator within granted authority. Build coordinates; implementers edit.
The existing build session is the single pipeline writer after handoff;
role agents keep their reporting commands. A controller only relays unless
explicitly granted acceptance authority; it cannot approve its own result.

On resume inspect the recorded writer's state and recent output, then reuse
it. If it exited, report that before arranging a restart. A timeout or unknown
state proves neither completion nor failed submission: inspect before resend.
Never start a duplicate writer or blindly replay a prompt.

## Conditional herdr mechanics

Only when herdr is chosen, read its installed skill and `herdr --skill`.
Create a tab in the selected workspace, preserving focus:

```sh
herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" --label "Build" --no-focus
```

Read the returned tab/root-pane IDs, start the chosen host with explicit
primary model/effort using its supported flags, and prompt it with the absolute
handoff brief. Record IDs and agent name. Inspect `herdr agent get` and
`herdr agent read` after a settled-state wait; idle alone is not the gate.
Native independent or manual handoffs preserve the same contract using their
own session identifiers and communication channel.

## Questions and acceptance

Surface actual questions and permission prompts to the designated contact;
answer routine questions from existing authorization. At the human gate,
report the current gate page, concrete app/artifact location, how to try it,
checks and limits, then wait. The contact opens the review location.

Relay notes, round requests and approval **unchanged** to the same inspected
writer; retain incoming words while it works. Notes alone start no round.
Only the user or designated acceptor within granted authority may accept:
`CLI accept <plan> --by <name> --words "<unchanged approval>"` binds the words
to the current judge, land and page. Then finish as configured when instructed,
without asking again for existing authorization. Continue watching through
rounds and finish.
