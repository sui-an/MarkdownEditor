---
name: build-verify
description: "Edit Swift source files, then run build.sh to compile and verify. Ensures every code change is followed by a successful build."
---

# Build-After-Fix Workflow

After editing any Swift source file in this project, always run the build script to verify compilation succeeds.

## When to Use

- After any `Edit` or `Write` to a `.swift` file under `Sources/`
- After fixing a bug or implementing a feature
- Before reporting a task as complete

## Steps

1. **Edit** the Swift source file(s)
2. **Run** the build script:
   ```bash
   cd /Users/chenhangan/Documents/temp/MarkdownEditor && bash build.sh 2>&1
   ```
3. **Check output**:
   - If build succeeds (no errors), the change is verified
   - If build fails, read the error messages, fix the issue, and repeat from step 1
4. **Report** the build result (success or error details)

## Notes

- `build.sh` uses `swiftc` directly — no Xcode IDE required, only Command Line Tools
- The project targets macOS 14.0+
- Build errors often indicate type mismatches, missing imports, or API availability issues
- Do NOT skip the build step — this project has no unit tests, so compilation is the primary verification
