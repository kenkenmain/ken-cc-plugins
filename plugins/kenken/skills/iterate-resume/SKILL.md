---
name: iterate-resume
description: Resume interrupted kenken iteration from saved state
---

# kenken Resume

> **For Claude:** Resume an interrupted kenken iteration from saved state.

## Actions

1. Read `.agents/kenken-state.json`

2. If no state found:
   - Display: "No kenken iteration in progress. Use `/kenken:iterate` to start."
   - Exit

3. If state found:
   - Display current status (use same format as `/kenken:iterate-status`)
   - Use AskUserQuestion:
     - "Resume iteration from Phase {X.Y} ({phase name})?"
     - Options:
       - "Yes, resume" - Continue from saved phase
       - "Restart current stage" - Go back to start of current stage
       - "Start fresh" - Clear state and start new iteration

4. Based on user choice:
   - **Resume:** Continue iterate workflow from currentPhase
   - **Restart stage:** Reset current stage phases to pending, start from first phase of stage
   - **Start fresh:** Delete state file, prompt for new task with /kenken:iterate

## Example Flow

```
User: /kenken:iterate-resume

Claude:
kenken Status

Task: Add user authentication
Stage: TEST (3/4)
Phase: 3.4 Run Tests [blocked - code logic error]

...

Resume iteration from Phase 3.4 (Run Tests)?

[Yes, resume]
[Restart current stage]
[Start fresh]

User selects: Restart current stage

Claude:
Restarting TEST stage. Note: Previous error was a code logic error.
Recommend restarting from IMPLEMENT stage to fix the underlying issue.

Proceed with TEST stage anyway, or restart from IMPLEMENT?

[Restart from IMPLEMENT (recommended)]
[Proceed with TEST]
```
