# Plan Review Prompt

<instructions>
Review the implementation plan for quality and completeness before implementation begins.
</instructions>

<context>
Plan location: {PLAN_PATH}
</context>

<focus_areas>

- Task granularity (each task should be 2-5 minutes of work)
- File paths are specific and accurate
- Code changes are complete (not placeholders)
- Plan follows DRY, YAGNI principles
- Logging requirements specified
- Dependencies and task order are correct
- Edge cases are covered
  </focus_areas>

<output_format>
Report findings with severity (HIGH/MEDIUM/LOW) and specific locations.
If you find NO issues, explicitly state: "Plan approved."
</output_format>
