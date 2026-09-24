# A fixture plan for preflight --parallel

Five phases whose *Changes* fields carry real backticked paths, arranged so the
write-sets answer both ways:

- phases 2 and 3 are disjoint — the canonical contract-parallel shape;
- phase 4 collides with phase 2 on `src/api/client.ts`;
- phase 5 carries two paths on one bullet, and names a third in the prose
  after the bullet's em-dash. Its *second* path collides with phase 3, and the
  one in its prose must not be read as a write at all;
- phase 6 wraps its bullet across two physical lines: one real path on the
  head, and phase 2's `src/api/client.ts` named in the prose on the
  continuation line, which must not be read as a write either — wherever the
  em-dash and the backtick happen to land once the bullet wraps.

The fenced block inside phase 1's *How* names a path that must never be read as
a write: a path inside a fence is an example, not a declaration.

## Phases

### Phase 1. The module both sides build against

**Becomes true**
- the shared module exists and exports the contract

**Changes**
- `src/shared/contract.ts` — the type and its guard

**How**
- plain TypeScript, for example:
```
**Changes**
- `src/fenced/never-a-write.ts`
```
- no runtime dependency is added

**Do not touch**
- —

**Frozen for later phases**
- `UserRecord` — the shape both sides read

**Verification**
- cases: TC-1

**Steps**
- [ ] write the module

### Phase 2. One side of the contract

**Becomes true**
- the client returns `UserRecord`

**Changes**
- `src/api/client.ts` — the fetch and its parse
- `src/api/client.test.ts` — its tests

**How**
- use `UserRecord` from `src/shared/contract.ts`

**Do not touch**
- —

**Frozen for later phases**
- —

**Verification**
- cases: TC-2

**Steps**
- [ ] write the client

### Phase 3. The other side of the contract

**Becomes true**
- the view renders a `UserRecord`

**Changes**
- `src/ui/UserCard.tsx` — the component
- `src/ui/UserCard.test.tsx` — its tests

**How**
- use `UserRecord` from `src/shared/contract.ts`

**Do not touch**
- —

**Frozen for later phases**
- —

**Verification**
- cases: TC-3

**Steps**
- [ ] write the component

### Phase 4. A phase that collides with phase 2

**Becomes true**
- the client retries once on a timeout

**Changes**
- `src/api/client.ts` — the retry
- `src/api/retry.ts` — the policy

**How**
- no new dependency

**Do not touch**
- —

**Frozen for later phases**
- —

**Verification**
- cases: TC-4

**Steps**
- [ ] add the retry

### Phase 5. Two paths on one bullet, and a path named in its prose

**Becomes true**
- the story renders the card

**Changes**
- `src/ui/UserCard.stories.tsx`, `src/ui/UserCard.tsx` — the story and the component, both reading the type from `src/shared/contract.ts`

**How**
- no new dependency

**Do not touch**
- —

**Frozen for later phases**
- —

**Verification**
- cases: TC-5

**Steps**
- [ ] write the story

### Phase 6. A wrapped bullet whose continuation names another phase's path

**Becomes true**
- the helper formats a user's display name

**Changes**
- `src/ui/UserCard.utils.ts` — a formatting helper, unrelated to phase 2's
  `src/api/client.ts`, which this phase does not write

**How**
- no new dependency

**Do not touch**
- —

**Frozen for later phases**
- —

**Verification**
- cases: TC-6

**Steps**
- [ ] write the helper
