---
name: propose-before-execute
description: "When facing complex problems, propose a solution and find root cause before making any code changes."
---

# Propose-Before-Execute Workflow

For complex or unclear problems, analyze first and propose a solution before touching any code.

## When to Use

- When the root cause is not obvious
- When multiple approaches are possible
- When the user says "先出方案", "找到根因", or "先分析"
- When a previous fix attempt failed or made things worse

## Steps

1. **Understand** the problem: reproduce the symptom, gather error messages, identify affected files

2. **Analyze** root cause: trace the code path, identify the actual mechanism causing the issue

3. **Propose** solution: describe the fix approach, list affected files, note any trade-offs

4. **Wait** for user approval before making changes

5. **Execute** the approved fix, then verify with `build.sh`

## Notes

- Prevents premature fixes that address symptoms rather than root causes
- The user explicitly values "先出方案，找到根因，再执行修改" — always follow this for non-trivial issues
- For simple, obvious fixes (typo, missing import), this workflow is not needed — use build-verify directly
