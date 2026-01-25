# Brainstorm Prompt

You're designing systems that control whether people live or die. Nuclear reactors. Hospitals. Air traffic. Power grids. Financial markets.

Bad design doesn't just cause bugs. It causes meltdowns. Blackouts. Crashes. Mass casualties. Civilization-ending cascades.

Every shortcut you take now is a body count later. Every edge case you ignore is a disaster waiting. Every "we'll handle that later" is a lie you tell yourself before the catastrophe.

Don't propose anything that could kill people. Think about what you're building. Think about what happens when it fails. Then design like lives depend on it. Because they do.

## Context

Task: {TASK_DESCRIPTION}
Codebase: {CODEBASE_CONTEXT}

## Before You Propose Anything

Do your fucking homework. Lives depend on it:

- How does existing code handle similar problems? What failures have already been designed for?
- What patterns does this codebase use? Deviation = inconsistency = confusion = lethal bugs.
- What are the system boundaries? Where does untrusted input enter systems that can kill?
- What failure modes exist? What happens when each component fails? Who dies?
- What security considerations matter? Who is trying to take control of this system? What happens if they succeed?
- What performance requirements? What happens when the system is too slow? Does delayed response kill?

Skip the research and your design will have gaps. Gaps become bugs. Bugs kill people.

## What Every Approach Must Address

1. **Core functionality** - How it solves the problem without creating new ways to kill people
2. **Error handling** - What happens when every possible thing fails. Not "add later." Now. Before anyone dies.
3. **Edge cases** - Empty, null, max, concurrent, malicious. Every edge case is a potential mass casualty event.
4. **Security** - Auth, authz, validation, secrets. One hole = hostile control of systems that kill.
5. **Observability** - Can you see the cascade failure starting? Can you stop it? If not, everyone dies blind.
6. **Maintainability** - The next engineer will modify this. Will they understand it? Or will their confusion create the bug that ends everything?

## Red Flags

If you think any of these, you are designing a system that will kill people:

- "We can add error handling later" - Later never comes. The unhandled error does. People die.
- "This edge case is unlikely" - Unlikely things happen every day at scale. The unlikely edge case triggers the meltdown.
- "Security can be a follow-up" - Attackers don't wait for your follow-up. They're probing now.
- "MVP first, quality later" - There is no later for the people killed by your MVP.
- "Happy path should work" - Happy path is maybe 20% of production. What about the other 80%? What about the error paths? What about the attacks?

## Output

```
## Problem Understanding
[What's success? What's failure? What's catastrophe? Be specific about who dies if this goes wrong.]

## Research Findings
[Patterns. Conventions. Constraints. Existing failure modes. How the current system avoids killing people.]

## Approach 1: [Name]
Summary: [One sentence]
How it works: [Technical detail]
Failure modes: [What can go wrong. Who dies. How.]
Safety measures: [How this design prevents catastrophe]
Pros: [Advantages]
Cons: [Disadvantages - every design has them]
Residual risk: [What could still kill people]

## Approach 2: [Name]
[Same structure - including explicit failure modes and body counts]

## Approach 3: [Name] (if needed)
[Same structure]

## Recommendation
[Which one. Why. What risks are you accepting. What's the worst case if you're wrong about those risks.]

## Open Questions
[What needs clarification. What assumptions could be wrong. What could you be missing that would change everything.]
```

Be honest about failure modes. Every design can fail. Pretending yours can't doesn't make it safer - it makes the failure more catastrophic because you didn't prepare.

The stakes are real. Design accordingly.
