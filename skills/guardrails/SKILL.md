---
name: guardrails
description: Set up Claude Code hooks to block dangerous git commands (push, reset --hard, clean, branch -D, etc.) before they execute. Use when user wants to prevent destructive git operations, add git safety hooks, or block git push/reset in Claude Code.
user-invocable: false
---

# Setup Git Guardrails

**Compatibility.** A Unix-like shell with `bash` — does not run natively on
Windows.

Sets up a PreToolUse hook that intercepts and blocks dangerous git commands before the agent executes them. The script it installs is identical in Claude Code and Codex — only where it gets registered differs.

## What Gets Blocked

- `git push` (all variants including `--force`)
- `git reset --hard`
- `git clean -f` / `git clean -fd`
- `git branch -D`
- `git checkout .` / `git restore .`

When blocked, the agent sees a message telling it that it does not have authority to access these commands.

## Steps

### 1. Ask which host

Ask the user: **Claude Code** or **Codex**? The rest of these steps differ only in where the hook gets registered.

### In Claude Code

#### 2. Ask scope

Ask the user: install for **this project only** (`.claude/settings.json`) or **all projects** (`~/.claude/settings.json`)?

#### 3. Copy the hook script

The bundled script is at: [scripts/block-dangerous-git.sh](scripts/block-dangerous-git.sh)

Copy it to the target location based on scope:

- **Project**: `.claude/hooks/block-dangerous-git.sh`
- **Global**: `~/.claude/hooks/block-dangerous-git.sh`

Make it executable with `chmod +x`.

#### 4. Add hook to settings

Add to the appropriate settings file:

**Project** (`.claude/settings.json`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-dangerous-git.sh"
          }
        ]
      }
    ]
  }
}
```

**Global** (`~/.claude/settings.json`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/block-dangerous-git.sh"
          }
        ]
      }
    ]
  }
}
```

If the settings file already exists, merge the hook into existing `hooks.PreToolUse` array — don't overwrite other settings.

### In Codex

#### 2. Copy the hook script

The bundled script is at: [scripts/block-dangerous-git.sh](scripts/block-dangerous-git.sh)

Copy it to `~/.codex/hooks/block-dangerous-git.sh` and make it executable with `chmod +x`. Codex has no separate project-level registration for this — one copy, used everywhere.

#### 3. Add hook to `~/.codex/hooks.json`

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.codex/hooks/block-dangerous-git.sh"
          }
        ]
      }
    ]
  }
}
```

If `~/.codex/hooks.json` already exists, merge this entry into its existing `hooks.PreToolUse` array — don't overwrite other settings.

### Either host

#### Ask about customization

Ask if user wants to add or remove any patterns from the blocked list. Edit the copied script accordingly.

#### Verify

Run a quick test:

```bash
echo '{"tool_input":{"command":"git push origin main"}}' | <path-to-script>
```

Should exit with code 2 and print a BLOCKED message to stderr.
