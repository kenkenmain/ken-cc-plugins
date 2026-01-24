# Final Review Prompt

<instructions>
Final validation before completion. Be thorough.
</instructions>

<context>
Task: {TASK_DESCRIPTION}
All changes: {ALL_CHANGES}
</context>

<focus_areas>

- Correctness and logic errors
- Documentation accuracy
- Edge cases and error handling
- Security concerns
- Logging quality
- Code quality and maintainability
  </focus_areas>

<output_format>
Report findings with severity (HIGH/MEDIUM/LOW) and file:line references.
If you find NO issues, explicitly state: "Approved for completion."
</output_format>
