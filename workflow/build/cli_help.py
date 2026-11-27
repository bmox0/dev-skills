"""Terminal help for the installed CLI."""

import argparse


ROOT = """Runweld {version}
Plan, build, verify, and finish work in a Git repository.
Each task has its own worktree, artifacts, and pinned Runweld release.

Usage
  runweld COMMAND [ARGS...]
  runweld help [COMMAND [SUBCOMMAND...]]
  runweld --release RELEASE COMMAND [ARGS...]

Start here
  runweld next                       See available actions in this checkout.
  runweld next TASK                  Inspect one task and its next actions.
  runweld next TASK --json           Read those actions as structured data.

  Start with `runweld next` in a project checkout or task worktree.
  In a task worktree, Runweld finds the task without an ID.
  If the project needs initialization, `next` points you to `runweld init`.

Examples
  runweld task start report-search --goal "Find reports by title"
  runweld next report-search
  runweld help task start

Project and tasks
  init                 Configure Runweld and the executor pair for this project.
  update               Update the installed CLI or select a release for new tasks.
  task start           Create or join a task. Use --bug for a reproduction.
  task resume          Inspect an existing task and its next actions.
  task path            Locate a task's artifacts.
  task setup           Preview or run task setup.
  task stage           Record progress in discovery.
  task complete        Close a task when the owner says its goal has been reached.
  task cancel          Close a task when the owner decides to stop the work.
  status               Inspect a plan or list current work.
  workflow             Show the stages, roles, and requirements.

  Completing or cancelling a task records the stage where it closed and
  preserves its history and artifacts. Accepting a prototype alone leaves
  the task open.

Planning and implementation
  grill, prototype     Resolve open questions or try a design before planning.
  spec, plan           Check project rules and review the proposed plan and run.
  approve              Validate and compile a plan without approving it.
  build, phase         Start approved work and record phase evidence.
  owner, grant         Find which phase owns a path or extend its allowed paths.
  decision             Record a decision, its source, and its rationale.
  brief, handoff       Write a worker brief or validate a Herdr destination.

Verification and finish
  gate, review         Open verification and complete an assigned review.
  finding, result      Record review findings and verification evidence.
  fix, round           Address findings or run another implementation round.
  verdict              Record the judge's decision on the current evidence.
  land                 Shape the verified changes into commits.
  page, note, accept   Present the result, record feedback, and capture acceptance.
  finish               Carry out the run's agreed Git integration and cleanup.

Guides and reference
  help agents          Read the agent workflow, roles, and approval boundaries.
  reference            Read a resource from the selected release.
  run, executor, path  Inspect run configuration, executor selection, or paths.

  Run a guide by name to read its instructions. For example, `runweld plan`
  prints the planning guide. `runweld plan --help` explains the command.

  Other guides include bug, epic, retro, domain-modeling, tdd, browser-test,
  verify, run-file, commit-work, writing-guides, implementer, reviewer,
  judge, build-verification, and human-review.

More help
  runweld help task             List task actions and when to use each one.
  runweld help task complete    Read requirements, effects, and examples.
  runweld task complete --help  Show the same command help.
  runweld --version             Show the CLI and project versions.
"""


ROUTE = ('Before compiling the plan, edit [route] in the task’s .run.toml to set grill or prototype to '
         '"ask" (interactive), "take" (required) or "skip" (bypass if not started). '
         'Omitted keys use the pinned release’s defaults. This does not erase progress or bypass required gates. '
         'Use runweld next ID to see the selected stage.')

CLOSURE = ('Run only on the task owner’s explicit decision. Supply the owner’s name and reason. '
           'Records the outcome and current stage, preserving the worktree, branch, artifacts, history and release pin. '
           'Does not approve code, integrate changes, or stop agents. A same-outcome retry returns the original record. '
           'The opposite outcome and later workflow writes are refused. Use runweld next ID to check the outcome '
           'and runweld task path ID to locate the artifacts.')


# Examples use PLAN, SHA and other uppercase placeholders for values supplied by the current assignment.
DETAILS = {
    "help": ("Read help for an exact command path, or omit the path for the overview. "
             "Use 'help agents --plan PLAN' for the selected run’s workflow and approval boundaries.",
             "help task complete", "help agents --plan PLAN"),
    "reference": ("Print an exact .md or .toml resource named by an instruction. Use --plan to read the run’s pinned copy.",
                  "reference references/SESSIONS.md --plan PLAN"),
    "handoff": ("Print handoff instructions, or validate the destination before dispatch. This does not launch a worker.",
                "handoff", "help handoff herdr"),
    "handoff herdr": ("Check that the workspace and pane match the task’s worktree. For a continuation, identify the existing agent.",
                      "handoff herdr PLAN --workspace WORKSPACE --pane PANE"),
    "next": ("Read the current stage, evidence, owner and available actions without advancing work. "
             "Omit ID in its worktree, or pass --plan PLAN. In the project checkout without an ID, closed tasks are not offered as work.",
             "next", "next report-search --json"),
    "init": ("Run in a Git checkout. Init previews detected commands without running them and writes shared project settings, "
             "the release lock and repository guidance. Supply the provider and both models for a new pair in non-interactive use. "
             "Commit the shared files, then run runweld next.",
             "init", "init --non-interactive --provider GPT --primary-model PRIMARY --secondary-model SECONDARY"),
    "update": ("Without a scope, an interactive terminal prompts. --cli installs the upstream CLI in this prefix. "
               "--project selects the installed default (or the exact installed RELEASE) for new tasks from an initialized project. "
               "Existing runs keep their pins. Check with runweld --version --verbose.",
               "update --project", "update --cli"),
    "path": ("Print the project’s local workflow directory or a category path without creating it.", "path handoff"),
    "task": ("Start or inspect a task, manage discovery, or close on the owner’s explicit decision. "
             "Choose an action below, then use runweld help task ACTION for its requirements.",
             'task start report-search --goal "Find reports by title"', "help task complete"),
    "task start": ("Run in an initialized Git checkout. A new ID creates a branch, worktree and local run files from the "
                   "project’s pinned release and HEAD unless --base is given. Select --provider when ambiguous. "
                   "Reusing the ID keeps the task and can add a new provider’s pair without changing recorded profiles. "
                   "On an approved run the new pair stays in the proposal until reapproved. Verify with runweld next ID.",
                   'task start report-search --goal "Find reports by title"', "task start report-search --provider GPT"),
    "task resume": ("Inspect the saved state and next actions without joining as a provider. Closed tasks still show their outcome and evidence.",
                    "task resume report-search --json"),
    "task path": ("Print the artifacts directory for an existing task or a path below it, without creating anything.",
                  "task path report-search", "task path report-search browser-test"),
    "task setup": ("Use --preview first to see the configured command, checkout and resources. Without it, prepare the worktree "
                   "and record the result. Ordinarily the run needs approval. Use --reproduction for active bug discovery before planning.",
                   "task setup PLAN --preview", "task setup PLAN --reproduction --preview"),
    "task stage": ("For a registered task, start the current discovery stage, save progress, finish with a result, "
                   "or skip an optional stage with --reason. Reproduction requires a red command and artifact and cannot be skipped. "
                   "Use runweld next ID for the available actions. " + ROUTE,
                   "task stage PLAN grill start", 'task stage PLAN grill skip --reason "Questions are settled"'),
    "task complete": ("Close a task whose goal has been reached. " + CLOSURE,
                      'task complete report-search --by "Project owner" --reason "The approved prototype met the goal"',
                      "next report-search"),
    "task cancel": ("Close a task whose work should stop. " + CLOSURE,
                    'task cancel report-search --by "Project owner" --reason "The work is no longer needed"',
                    "next report-search"),
    "spec": ("Read the guide or inspect project rules. Check a plan before compiling it. "
             "The normal build gate applies and commits the accepted spec changes.",
             "spec list", "spec check PLAN"),
    "spec list": ("List the project’s spec areas and rule IDs from the working tree without changing them.", "spec list"),
    "spec show": ("Read the rule and any archived plan entries that changed it. Find IDs with runweld spec list.",
                  "spec show distribution#project-lock"),
    "spec check": ("Read-only check of the plan’s Spec section against its base. Registered tasks use their recorded base. "
                   "Correct the reported file and line before compiling.", "spec check PLAN"),
    "spec write": ("Check the plan and apply its Spec section and archive entry to the worktree. Inspect the resulting diff. "
                   "Use the gate for normal tracked integration of the rules.", "spec write PLAN"),
    "approve": ("Strictly check the draft and compile its execution state. This writes records but is not human approval. "
                "Correct reported problems, then use runweld plan review PLAN to show the exact plan and run to the human.",
                "approve PLAN"),
    "status": ("Read a plan by path, or omit it for project inventory. Use --current for current workflow guidance "
               "and --json for evidence and actions in a machine-readable form.", "status --current", "status PLAN --json"),
    "workflow": ("Read the selected release’s workflow without advancing a task. Use --stage to narrow it to inputs, roles and transitions. "
                 "For a task’s actual stage and evidence, use runweld next.", "workflow --stage build-verification --json"),
    "plan": ("Run bare for the planning guide. Review the complete plan and run before recording the human’s decision. "
             "Approval starts no build.", "plan", "plan review PLAN"),
    "plan review": ("Show the proposal and its revision, including run settings, changes and the approval command. "
                    "Review that revision with the human. " + ROUTE, "plan review PLAN"),
    "plan approve": ("Record the human’s unchanged words for the displayed revision. Use --acceptor with --authority only "
                     "for delegated acceptance. If the proposal changed, review its new revision. Wait for a separate start instruction.",
                     'plan approve PLAN --revision REVISION --by "Project owner" --words "I approve this plan"'),
    "plan status": ("Set a status only when its required evidence exists. This cannot replace approval, acceptance or finish. "
                    "Inspect current evidence with runweld status PLAN.", "plan status PLAN draft"),
    "plan base": ("Record a new base for an eligible plan. Registered builds require the task’s original base. "
                  "Review the plan again after a base change.", 'plan base PLAN REF --note "Rebased the proposal"'),
    "build": ("Run bare for coordination instructions. Start only after the human has approved the plan and separately authorized the build.",
              "build", "help build start"),
    "build start": ("Open the approved build under the separate start instruction. Registered tasks already own a branch, base and worktree. "
                    "A repeat shows the existing assignment. Use runweld next --plan PLAN for the next action.",
                    "build start PLAN --provider GPT"),
    "phase": ("Coordinators start and verify phases. The assigned implementer records the commits and checks in a report.",
              "help phase report", "status PLAN"),
    "phase start": ("Open a phase once its dependencies are done. Inspect the resulting assignment with runweld next --plan PLAN.",
                    "phase start PLAN 1"),
    "phase report": ("The implementer records what became true, their commits and the check outcomes. "
                     "Repeat --check for each configured command. Re-reporting replaces the previous evidence. "
                     "The coordinator verifies it with phase done.", 'phase report PLAN 1 --became "Search finds titles" --commit SHA --check "scripts/check" passed'),
    "phase done": ("The coordinator verifies the reported commits, territory and configured checks before closing the phase. "
                   "Use runweld next --plan PLAN to see what is unlocked.", "phase done PLAN 1"),
    "owner": ("Find the running phase that owns a path, relative to the task tree or absolute.", "owner PLAN docs/cli.md"),
    "grant": ("Extend a running phase’s allowed paths as coordinator. A path owned by another running phase is refused. "
              "Check ownership with runweld owner PLAN PATH.", 'grant PLAN 1 docs/cli.md --note "Update the CLI reference"'),
    "decision": ("Record the question, source, answer, rationale and cost of being wrong. Include --phase for a phase ruling.",
                 'decision PLAN --phase 1 --by implementer --question "Keep the alias?" --from "CLI contract" --answer "Yes" --why "Existing callers" --cost "Old callers fail"'),
    "brief": ("Write the assigned role’s brief beside the plan and print its path. Read the selected model, effort and commands "
              "from the brief. This does not dispatch the role.", "brief implementer PLAN 1 --provider GPT"),
    "brief implementer": ("Write the phase assignment with its scope, skills, dependencies and report command.",
                          "brief implementer PLAN 1 --provider GPT"),
    "brief judge": ("Write the judge’s brief from the current review and verification evidence. "
                    "Complete the review and required results before briefing.", "brief judge PLAN --provider GPT"),
    "brief round": ("Write the running round’s notes and report command for its implementer.", "brief round PLAN --provider GPT"),
    "brief reviewer": ("Write the exact change range and any fix context for independent review.",
                       "brief reviewer PLAN --provider GPT"),
    "brief verify": ("Write the cases and result commands for Verify. A recheck includes previously failed cases and any --cases requested.",
                     "brief verify PLAN --provider GPT"),
    "brief fix": ("Write the open items assigned to the running fix and its report command.", "brief fix PLAN --provider GPT"),
    "gate": ("Open build verification once phase reports are verified. Gate start applies spec changes and runs or reuses full checks.",
             "help gate start", "status PLAN"),
    "gate start": ("The coordinator applies the spec changes, determines the gate level and records full checks for the current tip. "
                   "Use runweld status PLAN for results or recovery instructions. Do not start a second run while checks are active.",
                   "gate start PLAN"),
    "finding": ("Record a finding against the current review assignment and range. A Defect needs a location and its supporting evidence. "
                "Use --again for a Defect a fix took that still exists. Check the newest cycle with runweld status PLAN.",
                'finding PLAN --kind defect --where search.py:12 --text "Title is not matched" --assignment ASSIGNMENT --range BASE..HEAD'),
    "review": ("Run bare for review instructions. Record findings separately, then complete the assigned review even if it was clean.",
               "review", "help review complete"),
    "review complete": ("Mark the assigned range reviewed after recording any findings. Copy the assignment and range from the brief.",
                        "review complete PLAN --assignment ASSIGNMENT --range BASE..HEAD"),
    "result": ("Record a Done case for the current cycle and commit from the Verify brief. Passed or failed needs a capture. "
               "Give details for a failure or a case not reached. Inspect evidence with runweld status PLAN.",
               "result PLAN --case 1 --outcome passed --capture CAPTURE --cycle CYCLE --head SHA"),
    "fix": ("The coordinator opens a bounded fix for the current cycle’s open items. The implementer reports the changes. "
            "Completing the fix records full checks and leaves recheck evidence to review.",
            "help fix start", "help fix report"),
    "fix start": ("Take every open item in the newest cycle. Refused while a fix runs or the cap is reached. "
                  "Use the next action to prepare the worker’s brief.", "fix start PLAN"),
    "fix report": ("Record the fix’s outcome, tests and commits. Omit --commit if nothing changed. "
                   "Re-reporting replaces the previous evidence.", 'fix report PLAN --became "Search matches titles" --commit SHA'),
    "fix done": ("The coordinator closes a reported fix after applying the rules and recording full checks. "
                 "Use runweld status PLAN for the recheck or a check recovery.", "fix done PLAN"),
    "verdict": ("The judge records a verdict on current evidence. Decide each open item and Convention with "
                "let-through, round or question. The first verdict that judges evidence needs a prediction and engine. "
                "Read runweld judge for the rubric and runweld next --plan PLAN for what follows.",
                'verdict pass PLAN --report "No findings" --predicted pass --engine ENGINE'),
    "land": ("Run bare for landing instructions. Land the current judged changes as the commits in the shape file. "
             "Draft it first. If a hook changes the tree, inspect the diff and explicitly accept or revert.",
             "land draft PLAN", "land PLAN"),
    "land draft": ("Write the proposed commit shape. Review or edit it before landing.", "land draft PLAN"),
    "land accept": ("Keep a hook-changed landed tree after inspecting it. Record why the difference stays on the review page.",
                    'land accept PLAN --note "Formatter normalized imports"'),
    "land revert": ("Restore the backup branch tip after a land stop, and record the stop. Check the resulting state before retrying.",
                    'land revert PLAN --note "Hook changed the tested tree"'),
    "land now": ("Apply the prepared shape to the branch. Equivalent to runweld land PLAN. Check the result before writing the page.",
                 "land PLAN"),
    "page": ("Record a guide for the human tied to the judged and landed result. Supply a merge message or request title "
             "unless finishing with ff-only. Use --show to recover the recorded guide without writing.",
             "page PLAN --guide-file GUIDE.md --message \"Find reports by title\"", "page PLAN --show"),
    "accept": ("Only the authorized approver or designated acceptor may accept the current review page. "
               "Record their unchanged words and name. This marks the plan passed but does not integrate it.",
               'accept PLAN --by "Project owner" --words "I accept this result"'),
    "note": ("Record human feedback verbatim. Notes do not start a round. Use status to read the current workflow.",
             "help note add", "status PLAN"),
    "note add": ("Record and number a human note with its cause. A task-cause note is listed but not built in this run.",
                 'note add PLAN --text "Show the matching title" --cause feel-ui'),
    "note edit": ("Edit the words or cause of an open note, or classify its source after a round takes it. "
                  "Use the note number from the notes file.", 'note edit PLAN 1 --text "Show the exact title"'),
    "note drop": ("Drop an open note from future rounds. Use the note number from the notes file.", "note drop PLAN 1"),
    "round": ("An authorized round takes implementation notes, then gets its own verification cycle. "
              "A human note alone does not authorize a round.", "help round start", "help round report"),
    "round start": ("Start a judge-directed or human-authorized round. To resolve a finish conflict, "
                    "use --conflict with the problem instead of taking notes. Verify the assignment with runweld next --plan PLAN.",
                    "round start PLAN"),
    "round report": ("Record the round’s changes and checks before verification. Omit --commit if nothing changed. "
                     "Re-reporting replaces the previous evidence.", 'round report PLAN --became "Results show exact titles" --commit SHA'),
    "round done": ("After the report and note classification, apply the rules and record full checks. "
                   "Use runweld status PLAN for the next verification or recovery action.", "round done PLAN"),
    "finish": ("Use the run’s agreed ending after current acceptance. This can integrate locally or push and open a merge request. "
               "Run local finish from the surviving checkout. Inspect the integration and any pending cleanup in the result. "
               "Resolve the reported blocker and rerun finish to resume cleanup.", "finish PLAN --json"),
    "run": ("Inspect or check the companion .run.toml. The approved values stay frozen until reapproval. " + ROUTE,
            "run show PLAN", "run check PLAN"),
    "run new": ("Recover the initial run file only for an interrupted task entry. To start a new task use runweld task start. "
                "For a missing file on an existing task restore its saved copy.", "run new PLAN"),
    "run check": ("Read and validate the companion .run.toml. A valid file is silent. Fix reported problems and rerun the check.",
                  "run check PLAN"),
    "run show": ("Print run settings and any drift from the approved snapshot. Use --json for structured settings. " + ROUTE,
                 "run show PLAN --json"),
    "executor": ("Inspect the literal executor pair for a provider. This does not change the models or join a task.",
                 "executor show --provider GPT PLAN"),
    "executor show": ("Omit PLAN to read project defaults. With PLAN, read the recorded pair or, after approval, the frozen pair. "
                      "Use the reported model and effort exactly when dispatching that role.",
                      "executor show --provider GPT PLAN"),
    "grill": ("Run bare for interview instructions. Start or save the current interview, finish it when decisions are settled, "
              "or skip with a reason when optional. " + ROUTE, "grill start PLAN", 'grill skip PLAN --reason "Questions are settled"'),
    "prototype": ("Run bare for the prototype guide. Save evidence under the task’s artifacts and record the reviewed result. "
                  "Accepting a prototype does not complete the task. " + ROUTE, "prototype start PLAN",
                  'prototype done PLAN --result "Owner approved the prototype" --artifact ARTIFACT'),
    "bug": ("Run bare for investigation guidance. For a task started with --bug, save a failing test and the repeatable command "
            "at the registered base before planning. Reproduction cannot be skipped.", "bug start PLAN",
            'bug done PLAN --result "Title search fails" --command "scripts/test test/search.test.sh" --artifact RED_PATCH'),
    "browser-test": ("Run bare for the browser test guide. Use runweld browser-test help for the helper’s actions "
                     "and options without opening a browser.",
                     "browser-test", "browser-test help"),
}


def details_for(path):
    if path in DETAILS:
        return DETAILS[path]
    stage, _, event = path.partition(" ")
    label = "reproduction" if stage == "bug" else stage
    command = path + " PLAN"
    if event == "start":
        return (f"Enter the current {label} stage for a registered task. Omit PLAN inside its worktree.", command)
    if event == "save":
        return ("Record progress and any open questions without advancing. Repeat --question for each open question "
                "or use --clear-questions when resolved.", command + ' --result "Current evidence"')
    if event == "done":
        if stage == "bug":
            return ("Finish reproduction on the task’s registered base. Supply the result, failing command and saved red patch. "
                    "Check for Plan with runweld next.", DETAILS["bug"][-1])
        return ("Record the settled result after entering the stage. Resolve open questions before finishing. "
                "Check the next stage with runweld next.", command + ' --result "Decisions are settled"')
    if event == "skip":
        if stage == "bug":
            return ("This operation is refused. A bug task needs a red reproduction before planning. "
                    "Follow the current actions with runweld next.", "help bug done")
        return ("Skip this stage with a reason if the task’s route permits it. This preserves saved evidence. "
                "Check the next stage with runweld next.", command + ' --reason "Not needed"')
    return ("Print this guide and its included references without changing the task. "
            "Use --plan PLAN to select the task’s pinned guide.", path + " --plan PLAN")


class CommandParser(argparse.ArgumentParser):
    version = None

    def add_subparsers(self, **kwargs):
        kwargs.setdefault("title", "Commands")
        kwargs.setdefault("metavar", "COMMAND")
        action = super().add_subparsers(**kwargs)
        self.commands = action.choices
        return action

    def help_for(self, path):
        target = self
        for name in path:
            if name not in getattr(target, "commands", {}):
                parent = target.prog.removeprefix("runweld").strip()
                hint = f"runweld help {parent}".rstrip()
                self.exit(2, f"runweld: unknown command path {' '.join(path)!r}; see `{hint}`\n")
            target = target.commands[name]
        target.print_help()

    def format_help(self):
        if self.prog == "runweld":
            return ROOT.format(version=self.version)
        path = self.prog.removeprefix("runweld ")
        description, *examples = details_for(path)
        self.description = description
        help_text = super().format_help().rstrip()
        more = f"\n\nMore help\n  runweld help {path} COMMAND" if getattr(self, "commands", None) else ""
        return help_text + "\n\nExamples\n" + "\n".join(f"  runweld {example}" for example in examples) + more + "\n"
