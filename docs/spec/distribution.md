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

### project-lock — The project lock selects an exact verified release for new work and existing runs retain their release

Why: release contents already carry their integrity metadata and task changes must stay local

- Initialize and update a test project. Its new lock contains only format and release, an existing v2 project opens, older runs retain their pinned engine, and an altered package still fails verification.
- Configure two runs from one project to take different optional stages. Resume each in a fresh process and follow its selected route; compare project config and lock byte for byte before and after. Existing runs with no preference keep working.

### local-workflow — Shared project configuration and private workflow artifacts have distinct Git visibility

Why: a clone reuses project settings while execution records and evidence stay local.

- Commit the shared files, clone elsewhere and select Claude → supply only the missing Claude pair, retain the Codex pair and checks, and see no previous plans. Both clones select the same release.
- Start a task in an initialized checkout → Git ignores its plan, worktree and evidence under `.runweld/workflow/`. The project can track its config, lock and specs.

### task-artifacts — Each new task keeps its plan and execution records in one dated task directory

Why: humans can browse runs and retain evidence after the working tree is removed

- Create two tasks. Choose explicitly in the main checkout and resume by worktree. Retry across a date boundary. Each task has one dated plan directory holding its artifacts through finish.

### task-outcome — The owner can complete or cancel a task at its current stage and inspect the preserved result

Why: a task can reach its goal before Git integration or stop on its owner's decision

- Complete a disposable 7.2.0 task at Plan with an accepted Prototype artifact. A fresh CLI shows completed at Plan, opens the saved prototype, and omits the task from suggested work. History and release pin survive.
- Cancel a task with a compiled plan and reopen its status. The cancelled outcome and actual stage survive; another closure cannot overwrite it, and a stale workflow command cannot advance it. The branch and evidence remain accessible.

### command-help — Root, group and command help let an agent discover an operation, carry it out and verify the result

Why: a fresh agent needs accurate examples, effects and next steps directly in the terminal

- Read root help outside a project, find a task action, and invoke both help spellings. The text agrees, explains authorization and effects, gives a usable example, and shows how to check the outcome. An unknown command path gives a helpful usage error.
- Open the bare plan guide, its command help, and help agents for a selected run. Each produces the intended instructions; the root examples and grouped command names correspond to the shipped CLI.
