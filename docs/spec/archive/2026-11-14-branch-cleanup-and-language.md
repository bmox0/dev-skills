This is history; the rules that hold now are in `docs/spec/`.

# Plan: finish clears its backups, plans speak the project's language

## Result

Two things the owner hit on the 5.0 runs. Merged plans leave every `backup/<branch>-<n>` behind, and plans and specs come out in the conversation's language even when the project's documents are in another one. After this plan, `finish` offers to delete the plan's backups once the merge is done and deletes them only if the user says yes. A plan, and the rules and archive record it writes, are in the project's language: named in its `AGENTS.md`, otherwise the language of its documents, otherwise asked. The plugin is 5.0.1.

## Approach

`finish` gets one question after a merge. The project's language becomes a line in the Environment block that `plan` already reads for its commands. `plan` and the standalone `spec` mode write in that language, while the conversation and the gate page stay in the user's.

- Only the backups are offered for deletion. They are copies `land` made, and someone may still want one. The plan's branch, local or remote, is the user's to delete after the merge. The owner: "мы только подчищаем бэкапы… просто спросить, нужно ли это почистить".
- It is one question that names each backup, asked after the merge and before the retro offer. A no leaves them in place. On the merge-request path the question comes in step 1, once `gh pr view` says merged.
- Backups are never ancestors of the default branch once `land` has rewritten the branch, so a yes deletes them as they are.
- `**Language.** <language>` in the Environment block names the language the project's documents are written in; plans and specs follow it. It is a fact line like the others, not a prohibition.
- Without the line, the language is the one the documents in `docs/` are written in, `docs/spec/` first: a project may have moved its specs here from another tool. Commits, code comments, a README or a changelog do not decide it, because they often differ from the documents. With no documents, ask the user once. Either way, offer the line for `AGENTS.md`, as `plan` already does for a missing block.
- FORMAT's "the content is in the plan's language" becomes the project's language, by the same rule, so the standalone `spec` mode follows it without a plan to inherit it from.
- This repository's own Environment block gets `**Language.** English`.
- Word budgets for the touched files are raised as the change needs: the owner's call.

## Out of scope

- Deleting the plan's branch, local or remote.
- Note 1 (role files for the pipeline's stages, hooks) and note 4 (a full re-check after a small round): separate discussions, 5.1.
- Translating Daily's existing Russian rules: a plan in Daily, on its own `Language` line.
- Any hook.

## Done and Spec

```text
## Done

1. In a throwaway repo, a plan at `passed` on branch `feat/x` with `backup/feat/x-1` and `backup/feat/x-2`. Run `dev-skills:finish`, choose `--ff-only`, answer no to the backup question → the merge is in, `feat/x` and both backups remain. — you check
2. The same setup, answer yes → `git branch --list 'backup/feat/x-*'` is empty, `feat/x` remains, and the retro is offered after. — you check
3. In a project whose Environment block says `**Language.** English`, grill and plan a task while speaking Russian → the plan's Result, Approach, Done and `## Spec` are in English; the replies stay Russian. — you check
4. In a project with no `Language` line and English files in `docs/spec/`, run `dev-skills:plan` while speaking Russian → the plan is in English and the user is offered the `**Language.**` line. — you check
5. In a project with no `Language` line and nothing in `docs/`, run `dev-skills:plan` → it asks once which language, writes the plan in the answer and offers the line. — you check
6. `dev-skills:spec` standalone in a project with `**Language.** English`, speaking Russian → the plan-shaped file and the rules written to `docs/spec/` are in English. — you check
7. `scripts/check` and `scripts/test` → exit 0. The three manifests say `5.0.1`. `AGENTS.md` has `**Language.** English`. `environment-contract.md` shows the `Language` line in its block.
8. `dev-skills:spec` standalone, asked to record a rule → it asks only what must stay true here and why; the area, the rule's ID, `+`, `~` or `-`, and the wording are in the file without a question about them. — you check

## Spec

+ finish — Finish
  About: Merging a plan's branch at the end of the pipeline, and what is left behind.
+ finish#backups-delete-asks — After the merge the plan's backups are deleted only on the user's yes; the plan's branch is the user's
  Why: a backup is a copy someone may still want, and a branch is the user's to remove
  Done: 1, 2
+ spec — Spec
  About: The project's rules in `docs/spec/` and the plans that write them.
+ spec#project-language — Plans and the rules they write are in the project's language: the Language line, else the documents', else asked
  Why: the plan's Done and Spec become the project's lasting rules and archive, read by whoever works on it
  Done: 3, 4, 5, 6
```
