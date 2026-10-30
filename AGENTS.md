# pi-rex

`pi-rex` is a pi extension that records which conversation runs in each Rex
block, plus a script that reopens them after the Rex server restarts.

## Setup

Install dependencies and Lefthook once per clone:

```bash
bun install
uvx lefthook install
```

Pushing runs the quality gates automatically. You don't need to run checks
manually.

## Development

- Keep `README.md` in sync with user-facing behavior, the init snippet, and
  requirements.
- `bin/rex-resume` must run under macOS's bash 3.2 and BSD `date`: no
  associative arrays, no GNU-only options without a fallback.

## Release engineering

- Use `tenzir-ship` for changelog management and releasing.
- Add changelog entries for user-facing changes.
- Before releasing, ensure `main` is in sync with `origin/main`.
- To release, dispatch `.github/workflows/release.yaml` with a title and
  introduction.
