# Condition-Based Waiting

Flaky tests often guess at timing with arbitrary delays, which race under
load or in CI. Wait for the actual condition you care about, not a guess
about how long it takes.

## When to use

Use it whenever a test has an arbitrary delay (`setTimeout`, `sleep`) or is
flaky under load. Don't use it when the test is verifying actual timing
behaviour (debounce, throttle) — there, keep the timeout but document why
it's needed.

## Core pattern

```typescript
// Before
await new Promise(r => setTimeout(r, 50));
const result = getResult();

// After
await waitFor(() => getResult() !== undefined);
const result = getResult();
```

| Scenario     | Pattern                                              |
| ------------ | ----------------------------------------------------- |
| Wait for event | `waitFor(() => events.find(e => e.type === 'DONE'))` |
| Wait for state | `waitFor(() => machine.state === 'ready')`           |
| Wait for count | `waitFor(() => items.length >= 5)`                   |
| Wait for file  | `waitFor(() => fs.existsSync(path))`                 |

## Implementation

```typescript
async function waitFor<T>(
  condition: () => T | undefined | null | false,
  description: string,
  timeoutMs = 5000
): Promise<T> {
  const startTime = Date.now();
  while (true) {
    const result = condition();
    if (result) return result;
    if (Date.now() - startTime > timeoutMs) {
      throw new Error(`Timeout waiting for ${description} after ${timeoutMs}ms`);
    }
    await new Promise(r => setTimeout(r, 10));
  }
}
```

## Common mistakes

- Polling too fast (every 1ms) — poll every 10ms instead.
- No timeout — an unmet condition loops forever; always include one with a
  clear error.
- Reading state cached before the loop — call the getter inside the loop.

## When an arbitrary timeout is correct

Only after first waiting for the triggering condition, and only for a
duration based on known timing (not a guess), documented with why:

```typescript
await waitForEvent(manager, 'TOOL_STARTED');
await new Promise(r => setTimeout(r, 200)); // 2 ticks at 100ms intervals
```
