# The E2E gate

The gate checks data, sync, errors, races and code. The user judges look and feel.

## The level

`gate start` prints the level. The gate page names any paths that raised it.

| Level | The gate |
|---|---|
| small | the full checks; the first reviewer on primary; no e2e: every Done case is `you check` |
| normal | the full checks; the first reviewer on primary; e2e over Done |

## The pass

1. `gate start` ran the full checks. Red is on the list.
2. Together: `dev-skills:reviewer` handed `CLI brief reviewer --provider <provider> <plan>`, and, above
   small, a worker driving through `dev-skills:verify` handed `CLI brief verify --provider <provider>
   <plan>`. They record through those briefs. The reviewer records completion
   even when there are no findings. Each returns one line.
3. With nothing on the one list (`CLI status <plan>`), skip `fix start`. Else
   `CLI fix start <plan>` takes the one list: red checks, Defects, use cases
   failed. A case the code keeps from being reached is `failed`. Before `fix start`, re-drive a failed case once with `CLI brief verify --provider <provider> --cases N` when its capture does not match the command as written. One new implementer handed `CLI
   brief fix --provider <provider> <plan>` fixes all of it; `CLI fix done <plan>` re-runs the checks (long, like `gate start`). A case not
   reached for the environment goes on the gate page with what it needs;
   Conventions go to the judge, Observations folded to the gate page.
4. For the re-check, follow the range and executor in `CLI brief reviewer
   --provider <provider>`. At once a fresh worker gets `CLI brief verify --provider <provider>
   [--cases N,…]` with the cases the fix touched. When that brief says "no case
   to drive", dispatch no worker; the judge brief says so.
   A fix takes new items. Survivors appear under Open.
5. `CLI status <plan>` names pending evidence. With current records, brief the
   judge (`judge.md`).
