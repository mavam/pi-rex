# 🦖 pi-rex

A [Pi](https://pi.dev) extension that reopens your conversations in
[Rex](https://www.superlogical.com/rex) terminal blocks after the Rex server
restarts.

Rex restores sessions, tabs, splits, and working directories on its own, but not
the programs that ran in them. pi-rex remembers which Pi conversation ran in
each block and resumes it in place.

## 🚀 Installation

```sh
pi install npm:pi-rex
```

## ✨ Usage

The extension installs its resume scripts under `~/.local/state/pi-rex` the
first time Pi starts, and keeps them current after updates. Add these lines to
Rex's `init.lua` so Rex runs it when its server starts:

```lua
local state = os.getenv("XDG_STATE_HOME") or os.getenv("HOME") .. "/.local/state"
rex.exec.start({ "bash", state .. "/pi-rex/rex-resume" }, { detach = true })
```

Rex runs it whenever its server starts.

From then on, each Pi in a Rex block records its conversation after its first
reply. When the server restarts and Rex brings the blocks back, pi-rex types
`pi --session <id>` into every block that had a recorded conversation. You pick
up where you left off, in the same block and directory.

pi-rex waits until each block's shell sits at its prompt before typing, so a
slow shell startup, such as entering a devenv or direnv environment, doesn't
swallow the command. If Pi had moved its conversation to another directory,
such as a worktree, pi-rex changes there first.

What gets resumed:

- Conversations that were open when the server stopped or crashed.
- Conversations you switched to with `/resume` or `/fork`.

What doesn't:

- Conversations you quit with <kbd>Ctrl</kbd>+<kbd>D</kbd> or replaced with
  `/new`.
- Pis that never got a reply, because they have no conversation on disk yet.
- Other programs; they come back as a plain shell.

pi-rex only acts on a server that started within the last two minutes, and once
per server instance. It never types into a block where Pi or another program
already runs.

## 🧰 Requirements

- Rex for macOS, version 0.1.0-preview.23 or later, which restores sessions
  across server restarts.
- `bash` and the `rex` CLI. The script finds the CLI inside the installed Rex
  app if it isn't on `PATH`.

## 🩺 Troubleshooting

The script logs what it did to `~/.local/state/pi-rex/log`. Records live next to
it, one file per block.

If a conversation didn't come back, check that the block had a reply before the
restart: `ls ~/.local/state/pi-rex`.
