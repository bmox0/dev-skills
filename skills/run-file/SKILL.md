---
name: run-file
description: Write the run file a plan is built under — what the run may do, how it is checked and how it ends. Use after a grill and its prototype, before the plan, or when a plan's run file is to change.
---

# Run file

In Codex, read [CODEX.md](../../references/CODEX.md) first.

This session is the orchestrator. The run file holds what the user is asked
once, up front, so nothing pulls them in mid-run. `CLI` is
`python3 "<this skill's directory>/../build/pipeline.py"`. The keys:
[example.run.toml](references/example.run.toml).

1. **Name it.** Choose the branch the plan will be built on. The file is
   `.ai-workflow/plans/YYYY-MM-DD-<slug>.run.toml`, today's date and the branch
   with each `/` written `-`; the plan takes the same name with `.md`. If
   `git check-ignore -q .ai-workflow/plans/x` fails, add `.ai-workflow` to
   `$(git rev-parse --git-path info/exclude)`.
2. **Copy.** `CLI run new <plan path>` copies the project's newest run file,
   else the example. A first run (`copied from …example.run.toml`): fill
   `[checks]` from the `AGENTS.md` Environment block, which code never reads.
3. **Ask once.** Send one message with the copied values (`CLI run show
   <plan path>`). Ask only what differs from this task, and what the task needs
   that no key covers: a `[run]` key for it. E2E sets up nothing beyond the keys, so
   a stand-in, fixture or account the checks need is a key, asked here. Edit the
   file with the answers.
4. **Secrets.** For each new secret, in the step 3 message when an answer
   brings it, ask: written directly, or as `keychain:<service>/<account>`, which
   stays as written.
5. **Check.** `CLI run check <plan path>` until it is silent: the file is done.

Then hand over to `dev-skills:plan`, which reads this file. After approval a
change is an edit to the file and `CLI approve` again.
