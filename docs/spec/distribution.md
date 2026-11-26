# Distribution

The CLI delivers the selected release’s workflow instructions.

### shared-resources — CLI installations expose the same workflow guides, roles, references and CLI from the intended revision

Why: instructions without their resources do not install the workflow

- Load complete packages from relocated paths → command instructions, role sources, references and CLI resolve to the intended revision; target-project profiles/artifacts stay outside package code.
- In a Qoder session, invoke the CLI and dispatch all three roles → capture loaded sources, role identity, requested/reported settings and result delivery; unavailable settings or authentication are not passed

### system-cli — Humans and agents can enter with help and resume with next using the installed release

Why: a new terminal or agent needs a discoverable path through the entire task

- From a clean checkout follow help and next through init twice. Project checks, bootstrap and URL survive, format passes and the second init produces no diff.
- Use a fresh process to follow a review finding through fix, recheck, judge and human feedback round. Execute the supplied argv in its indicated cwd. Find the brief and reporting command for work. Distinguish a question for the human from waiting on the assigned worker. Text and JSON agree on each action.
- Start on release A, select B for new tasks, resume the first from a fresh session. Commands and roles resolve on this machine to the task's release. A second task uses B.
- Give a fresh agent only the instruction to run next mid-task. Ask it to explain the goal, what has been decided, what evidence justifies the current action, who owns it and what will unlock the next step. Compare its answers with the saved records and observe it continue from the resulting report or human decision

### project-lock — The project locks the workflow release and `runweld update --project` changes that selection for new work

Why: collaborators must share reproducible rules and preserve ongoing work across updates.

- Commit the shared files, clone elsewhere and select Claude → supply only the missing Claude pair, retain the Codex pair and checks, and see no previous plans. Both clones select the same release.
- Change only the reviewer instructions, install the new build and update the project → the release ID, reviewer digest and consuming stage digests change, other components stay pinned, and a new task refuses a lock with an edited digest.
- Change only the interview guide and update → only grill changes in the stage list; its inputs name the changed file. Inspect build verification → its conditional web/Electron tools include browser-test.
- Install releases A and B, start a run on A and call `runweld update --project` → the project lock moves to B, new work uses B, and the active run and its briefs still use A. An unavailable or damaged release gives an actionable error and leaves the prior lock or run intact.

### local-workflow — Shared project configuration and private workflow artifacts have distinct Git visibility

Why: a clone reuses project settings while execution records and evidence stay local.

- Commit the shared files, clone elsewhere and select Claude → supply only the missing Claude pair, retain the Codex pair and checks, and see no previous plans. Both clones select the same release.
- Start a task in an initialized checkout → Git ignores its plan, worktree and evidence under `.runweld/workflow/`. The project can track its config, lock and specs.

### task-artifacts — Each new task keeps its plan and execution records in one dated task directory

Why: humans can browse runs and retain evidence after the working tree is removed

- Create two tasks. Choose explicitly in the main checkout and resume by worktree. Retry across a date boundary. Each task has one dated plan directory holding its artifacts through finish.
