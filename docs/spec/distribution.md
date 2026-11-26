# Distribution

One complete shared package exposed through native integration metadata.

### shared-resources — Native installations expose the same complete skills, roles, references and CLI from the intended revision

Why: instructions without their resources do not install the workflow

- Load complete packages from relocated paths → common skills, role sources, references and CLI resolve to the intended revision; target-project profiles/artifacts stay outside package code.
- After login, load the package in real Qoder and dispatch all three roles → capture loaded sources, role identity, requested/reported settings and result delivery; unavailable settings or authentication are not passed

### system-cli — A standalone installation provides Runweld and all release-owned workflow instructions to humans and agents

Why: a new harness needs only one lightweight entry skill to use the same process.

- Install outside the project and run `runweld init` in a plain terminal → select one provider, enter its pair and checks, receive a usable config, lock, ignore rule and short AGENTS pointer. Repeat init or interrupt and retry → user-authored content and profiles survive.
- Follow `runweld help agents` through planning, approved build, review, E2E, judge, land, human gate and authorized finish with plugins and hooks disabled → the appropriate role receives its instructions, human receives a concrete guide, and release rules reject a premature transition or attempted project graph override.
- In a real Codex project and a colleague’s Claude clone, use the documented skill installation and ask “используй runweld” → each agent discovers its next action using the single skill. Review the guide for the actual build
- Attempt to install into a prefix with an unrelated executable named `runweld` → the installer refuses and leaves that executable untouched.

### project-lock — The project locks the workflow release and `runweld update --project` changes that selection for new work

Why: collaborators must share reproducible rules and preserve ongoing work across updates.

- Commit the shared files, clone elsewhere and select Claude → supply only the missing Claude pair, retain the Codex pair and checks, and see no previous plans. Both clones select the same release.
- Change only the reviewer instructions, install the new build and update the project → the release ID and reviewer digest change, every other component digest stays the same, and a new task refuses a lock with an edited digest.
- Install releases A and B, start a run on A and call `runweld update --project` → the project lock moves to B, new work uses B, and the active run and its briefs still use A. An unavailable or damaged release gives an actionable error and leaves the prior lock or run intact.

### local-workflow — Shared project configuration and private workflow artifacts have distinct Git visibility

Why: a clone reuses project settings while execution records and evidence stay local.

- Commit the shared files, clone elsewhere and select Claude → supply only the missing Claude pair, retain the Codex pair and checks, and see no previous plans. Both clones select the same release.
- Adopt a legacy checkout with historical and active runs, compiled approvals, an issued command and a linked worktree → the command still works, inventory finds each run once, recorded approvals and evidence survive, and retrying migration preserves all files. Git ignores plans, evidence and scratch files under `.runweld/workflow/`. The project can track `.runweld/config.toml`, `.runweld/runweld.lock` and its specs.
