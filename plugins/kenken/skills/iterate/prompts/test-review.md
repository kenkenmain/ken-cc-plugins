# Test Review Prompt

<instructions>
Review the tests for quality and completeness.
</instructions>

<context>
Test files: {TEST_FILES}
Project testing instructions: {TEST_INSTRUCTIONS}
</context>

<focus_areas>

- Tests follow project conventions
- Happy path covered
- Edge cases covered
- Error conditions tested
- Meaningful assertions
- No false positives (tests that always pass)
  </focus_areas>

<output_format>
Report findings with severity (HIGH/MEDIUM/LOW) and file:line references.
If you find NO issues, explicitly state: "Tests approved."
</output_format>
