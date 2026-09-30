# Defense-in-Depth Validation

A single validation point feels sufficient after a bug caused by invalid
data, but it can be bypassed by another code path, a refactor, or a mock.
Validate at every layer the data passes through, so the bug becomes
structurally impossible.

## The four layers

1. **Entry point validation** — reject obviously invalid input where it
   enters, e.g. an empty or nonexistent directory:

   ```typescript
   function createProject(name: string, workingDirectory: string) {
     if (!workingDirectory || workingDirectory.trim() === '') {
       throw new Error('workingDirectory cannot be empty');
     }
     if (!existsSync(workingDirectory)) {
       throw new Error(`workingDirectory does not exist: ${workingDirectory}`);
     }
   }
   ```

2. **Business logic validation** — check the data still makes sense for this
   specific operation, even after it passed entry:

   ```typescript
   function initializeWorkspace(projectDir: string, sessionId: string) {
     if (!projectDir) {
       throw new Error('projectDir required for workspace initialization');
     }
   }
   ```

3. **Environment guards** — block dangerous operations in specific contexts,
   e.g. refusing to run outside a temp directory during tests:

   ```typescript
   if (process.env.NODE_ENV === 'test' && !resolve(directory).startsWith(resolve(tmpdir()))) {
     throw new Error(`Refusing git init outside temp dir during tests: ${directory}`);
   }
   ```

4. **Debug instrumentation** — log the context (value, cwd, stack) right
   before the dangerous operation, so a bypass of the first three layers is
   still legible in forensics.

## Applying the pattern

Trace where the bad value originates and where it's used, list every
checkpoint it passes through, add validation at each one, then test each
layer in isolation — bypass layer 1 and confirm layer 2 still catches it, and
so on.

Each layer catches what the others miss: a different code path can skip
entry validation, a mock can skip business logic, a platform-specific edge
case needs the environment guard. Don't stop at one validation point.
