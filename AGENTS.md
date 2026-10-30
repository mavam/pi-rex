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
- `bin/rex-resume` must run under macOS's bash 3.2. It only waits for the
  server; the resume logic lives in `bin/rex-resume.lua`, which Rex runs with
  Lua 5.1 through `rex do`.
- The tests run the Lua script against a fake Rex and need `luajit` (or another
  Lua interpreter) on `PATH`.

## Release engineering

- Use `tenzir-ship` for changelog management and releasing.
- Add changelog entries for user-facing changes.
- Before releasing, ensure `main` is in sync with `origin/main`.
- To release, dispatch `.github/workflows/release.yaml` with a title and
  introduction.
