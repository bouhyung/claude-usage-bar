---
name: release
description: Build, push, and create a GitHub release with bilingual release notes
disable-model-invocation: true
argument-hint: [version e.g. 0.2.0]
allowed-tools: Read, Grep, Glob, Bash, Edit
---

# Release Skill

Create a new release for ClaudeUsageBar.

Version argument: `$ARGUMENTS` (e.g. `0.2.0`)

## Steps

### 1. Validate version argument
- If no version is provided, error out and ask the user.
- Version format must be semver (e.g. `0.2.0`).

### 2. Update version in Info.plist
- Update `CFBundleVersion` and `CFBundleShortVersionString` in `Resources/Info.plist` to `$ARGUMENTS`.
- If the version is already correct, skip this step.

### 3. Check and commit any uncommitted changes
- Run `git status` to check for uncommitted changes.
- If there are changes (including the Info.plist version bump), stage and commit them.
- Commit message: `Set version to $ARGUMENTS`

### 4. Push to remote
- Push all commits to `origin main`.

### 5. Build .app bundle
- Run `scripts/build.sh` to create the full `.app` bundle at `dist/Claude Usage Bar.app`.
  - This script handles: release build, .app structure, Info.plist copy, icon copy, and ad-hoc code signing.
- Create a zip of the .app for upload:
  ```
  cd dist && zip -r "ClaudeUsageBar-v$ARGUMENTS-macos-arm64.zip" "Claude Usage Bar.app" && cd -
  ```

### 6. Gather release notes context
- Run `git tag --sort=-v:refname` to find the previous release tag.
- Run `git log --oneline <previous-tag>..HEAD` to get all commits since the last release.
- Analyze each commit to write meaningful release notes.

### 7. Create GitHub release
- Use `gh release create v$ARGUMENTS` with the .app zip attached:
  ```
  gh release create v$ARGUMENTS dist/ClaudeUsageBar-v$ARGUMENTS-macos-arm64.zip
  ```
- Release notes must be **bilingual (English + Korean)** in the following format:

```
## What's Changed

### Bug Fixes / 버그 수정
- **English description** — Korean description

### Improvements / 개선사항
- **English description** — Korean description

### New Features / 새 기능
- **English description** — Korean description

## Install / 설치

Download `ClaudeUsageBar-v$ARGUMENTS-macos-arm64.zip`, unzip, and move `Claude Usage Bar.app` to `/Applications`.

**Full Changelog**: https://github.com/bouhyung/claude-usage-bar/compare/<prev-tag>...v$ARGUMENTS
```

- Only include sections that have actual changes (skip empty sections).
- Each item should have both English and Korean on the same line, separated by ` — `.
- Be concise but descriptive. Focus on user-facing changes.

### 8. Confirm
- Print the release URL when done.
