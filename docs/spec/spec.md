# Spec

The project's rules in `docs/spec/` and the plans that write them.

### project-language — Plans and the rules they write are in the project's language: the Language line, else the documents', else asked

Why: the plan's Done and Spec become the project's lasting rules and archive, read by whoever works on it

- In a project whose Environment block says `**Language.** English`, grill and plan a task while speaking Russian → the plan's Result, Approach, Done and `## Spec` are in English; the replies stay Russian.
- In a project with no `Language` line and English files in `docs/spec/`, run `dev-skills:plan` while speaking Russian → the plan is in English and the user is offered the `**Language.**` line.
- In a project with no `Language` line and nothing in `docs/`, run `dev-skills:plan` → it asks once which language, writes the plan in the answer and offers the line.
- `dev-skills:spec` standalone in a project with `**Language.** English`, speaking Russian → the plan-shaped file and the rules written to `docs/spec/` are in English.

### one-parser — The plan is parsed in one place, the pipeline's CLI, whose `spec` commands replace `spec.py`

Why: two parsers of one plan drift apart (GSD ADR-3524)

- Run `scripts/check` and `scripts/test` → both exit 0. `skills/spec/spec.py` is gone, and nothing outside `.ai-workflow/` and `docs/spec/` names it. `git diff a0a41ac -- test/cli/spec.test.sh` touches only the entry and the program's name in one message.
- In a throwaway repo, run `spec list`, `show`, `check` and `write` through `pipeline.py`, and through `spec.py` from `a0a41ac` → both give the same output, exit codes and files.
