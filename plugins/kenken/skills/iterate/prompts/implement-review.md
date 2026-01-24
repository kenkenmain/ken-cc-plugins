# Implementation Review Prompt

<instructions>
Review the implementation for correctness and quality.
</instructions>

<context>
Files changed: {CHANGED_FILES}
Base SHA: {BASE_SHA}
Head SHA: {HEAD_SHA}
</context>

<focus_areas>

- Logic errors and bugs
- Edge cases and error handling
- Logging quality (meaningful messages, error context)
- Code follows repo conventions
- No security vulnerabilities
</focus_areas>

<output_format>
Report findings with severity (HIGH/MEDIUM/LOW) and file:line references.
If you find NO issues, explicitly state: "Implementation approved."
</output_format>
