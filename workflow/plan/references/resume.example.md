# Approve and resume a task

In this example, the human wants to rebind keyboard shortcuts in Settings.
The planner saved the [complete plan](example.md) and
[run configuration](../../run-file/references/example.run.toml).
Run these commands against the plan path printed at task entry:

```sh
runweld spec check <plan>
runweld approve <plan>
runweld plan review <plan>
```

Present both documents together. Copy the revision from the review output and
ask for one decision. After the human approves, record their name and unchanged
words using the printed command:

```sh
runweld plan approve <plan> --revision <revision> --by "Jamie Lee" --words "I approve this plan and its run configuration."
```

Nothing has started. When the human separately instructs the coordinator to
start, run `runweld build start <plan> --provider <provider>`. Repeating that
command shows the existing assignment. From a fresh session, use
`CLI next` inside the task worktree or `runweld next <task-id>` in the
main checkout. If the plan or configuration changes, review the diff and
obtain approval of the new revision.
