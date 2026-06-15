---
name: code-review-fix
description: "After functionality is working, perform a structured code review, then fix all approved issues in one pass."
---

# Code Review → Fix Workflow

After a feature or bug fix is working, perform a code review to catch remaining issues, then fix everything the user approves.

## When to Use

- After completing a feature implementation
- After a bug fix is verified (build passes)
- When the user says "代码审查", "review", "清理一下", or similar

## Steps

1. **Review** the changed files for:
   - Dead or unused code (unused variables, unreachable branches, commented-out code)
   - Redundant or duplicated logic
   - Debug artifacts (print/NSLog statements left in, test data hardcoded)
   - Potential bugs (force unwraps, missing error handling, race conditions)
   - Performance issues (unnecessary allocations, blocking main thread, expensive operations in loops)
   - Design issues (tight coupling, violated patterns, missing abstractions)

2. **Present** findings as a numbered list with file paths and line references

3. **Wait** for user approval — the user typically says "修复" or "全部修复" to approve all suggestions

4. **Fix** all approved items in one pass, then run `build.sh` to verify

## Notes

- This project's user pattern: after functionality works, request review → approve all → fix all
- Use `build.sh` after all fixes to ensure nothing broke
- Focus on actionable issues — don't nitpick style unless it impacts readability significantly
