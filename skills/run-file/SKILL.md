---
name: run-file
description: Write the run file a plan is built under — what the run may do, how it is checked and how it ends. Use after a grill and its prototype, before the plan, or when a plan's run file is to change.
---

# Run file

Read shared `AGENTS.md` and the executor contract:
[SESSIONS.md](../../references/SESSIONS.md).

The run file records the agreed permissions and ending. `CLI` is
`python3 "<this skill's directory>/../build/pipeline.py"`. The keys:
[example.run.toml](references/example.run.toml).

1. **Name it.** Choose the branch. Use
   `.ai-workflow/plans/YYYY-MM-DD-<slug>.run.toml`, today's date and the branch
   with each `/` written `-`; the plan takes the same name with `.md`. If
   `git check-ignore -q .ai-workflow/plans/x` fails, add `.ai-workflow` to
   `$(git rev-parse --git-path info/exclude)`.
2. **Copy.** `CLI run new <plan path>` copies the project's newest run file,
   else the credential-free example, snapshotting all current
   AGENTS Executors profiles. `CLI executor show --provider <provider>`
   selects primary/secondary before approval. A first run (`copied from …example.run.toml`): fill
   `[checks]` from the `AGENTS.md` Environment block, which code never reads.
3. **Ask once.** Send one message with the copied values (`CLI run show
   <plan path>`). Ask what differs and add `[run]` keys for missing task needs, including
   fixtures and accounts: E2E sets up only these keys. Apply the answers.
4. **Secrets.** For each new secret, in the step 3 message when an answer
   brings it, ask: written directly, or as `keychain:<service>/<account>`, which
   stays as written.
5. **Check.** `CLI run check <plan path>` until it is silent: the file is done.

Then `dev-skills:plan` validates and asks explicit run approval with
`CLI run approve <plan> --by <name> --words "<unchanged approval>"`, then summary
approval. After approval readers use the frozen snapshot; changing it requires
renewed run and summary consent, not compilation alone.
