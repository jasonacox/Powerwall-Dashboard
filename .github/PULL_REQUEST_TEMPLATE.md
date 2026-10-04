## What and why

<!-- What does this change, and why? Link the issue (e.g. Fixes #123). Dashboard or CLI design changes should be discussed in an issue first. -->

## Checklist

- [ ] Simple and focused; no unrelated changes
- [ ] Backward compatible with existing installs (or discussed with the maintainers first)
- [ ] User settings stay in local untracked files (`.sample` pattern); no user edits to tracked core files
- [ ] Scripts work on Linux, macOS, WSL, Synology and Raspberry Pi (Bash 3.2, `sed -i.bak`, no GNU-only flags)
- [ ] Dashboard/CLI look and wording match the existing style
- [ ] `VERSION` and `upgrade.sh` bumped and `RELEASE.md` updated (or this is docs-only)
- [ ] Docs updated and clear for novice and expert users
- [ ] No secrets or local files committed

## How it was tested

<!-- Platforms, versions, and commands or scripted input used. -->
