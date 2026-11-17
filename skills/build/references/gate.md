# The E2E gate

The gate checks what trying the app misses: data, sync, errors, races and code. Looks and feel are the user's, at the human gate.

## The level

`gate start` prints it; when a changed path raised it, say so in a line on the gate page.

| Level | The gate |
|---|---|
| small | the full checks; the first reviewer on primary; no e2e: every Done case is `you check` |
| normal | the full checks; the first reviewer on primary; e2e over Done |

## The pass

1. `gate start` ran the full checks. Red is on the list.
2. Together: `dev-skills:reviewer` handed `CLI brief reviewer --provider <provider> <plan>`, and, above
   small, a worker driving through `dev-skills:verify` handed `CLI brief verify --provider <provider>
   <plan>`. They record through those briefs; their final
   message is one line.
3. With nothing on the one list (`CLI status <plan>`), skip `fix start`. Else
   `CLI fix start <plan>` takes the one list: red checks, Defects, use cases
   failed. A case the code keeps from being reached is `failed`. Before `fix start`, re-drive a failed case once with `CLI brief verify --provider <provider> --cases N` when its capture does not match the command as written. One new implementer handed `CLI
   brief fix --provider <provider> <plan>` fixes all of it; `CLI fix done <plan>` re-runs the checks (long, like `gate start`). A case not
   reached for the environment goes on the gate page with what it needs;
   Conventions go to the judge, Observations folded to the gate page.
4. A targeted re-check, on the fix's commits: the reviewer on secondary handed `CLI
   brief reviewer --provider <provider>`, and at once a fresh worker handed `CLI brief verify --provider <provider>
   [--cases N,…]` with the cases the fix touched. When that brief says "no case
   to drive", dispatch no worker; the judge brief says so.
   A fix that code still allows takes only what is new; what survived it
   is under Open on the gate page.
5. The judge reads the results (`judge.md`).
