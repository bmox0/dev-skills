# Spec

The project's rules in `docs/spec/` and the plans that write them.

### project-language — Plans and the rules they write are in the project's language: the Language line, else the documents', else asked

Why: the plan's Done and Spec become the project's lasting rules and archive, read by whoever works on it

- In a project whose Environment block says `**Language.** English`, grill and plan a task while speaking Russian → the plan's Result, Approach, Done and `## Spec` are in English; the replies stay Russian.
- In a project with no `Language` line and English files in `docs/spec/`, run `dev-skills:plan` while speaking Russian → the plan is in English and the user is offered the `**Language.**` line.
- In a project with no `Language` line and nothing in `docs/`, run `dev-skills:plan` → it asks once which language, writes the plan in the answer and offers the line.
- `dev-skills:spec` standalone in a project with `**Language.** English`, speaking Russian → the plan-shaped file and the rules written to `docs/spec/` are in English.
