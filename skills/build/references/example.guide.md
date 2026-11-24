Open the worktree at `/tmp/review-export` on the `feat/export-preview` branch.
Run `scripts/preview`, then go to `http://localhost:4173/export`.
Say whether you accept the limitation below or want another round.

#### What to check

- **Done 1** Click Download CSV → The browser downloads `report.csv` with Date and Amount columns.
- **Done 2** Open Export for an empty period → The page shows “No data” and disables Download CSV.
- **Check 1** Download the report twice → Both files contain the same rows, newest first as chosen during implementation.

#### What to decide

- Defect `gate D1` can cause the browser to hang when exporting more than 10,000 rows. Accept the build and defer the fix, or ask for the fix before accepting.
