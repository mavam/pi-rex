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

The extension installs the resume script at `~/.local/state/pi-rex/rex-resume`
the first time Pi starts, and keeps it current after updates. Add these lines to
Rex's `init.lua` so Rex runs it when its server starts:

```lua
local state = os.getenv("XDG_STATE_HOME") or os.getenv("HOME") .. "/.local/state"
rex.exec.start({ "bash", state .. "/pi-rex/rex-resume" }, { detach = true })
```

Rex runs it at its next server start; reloading the configuration doesn't resume
anything.

From then on, each Pi in a Rex block records its conversation after its first
reply. When the server restarts, a few seconds after Rex brings the blocks back,
pi-rex types `pi --session <id>` into every block that had a recorded
conversation. You pick up where you left off, in the same block and directory.

What gets resumed:

- Conversations that were open when the server stopped or crashed.
- Conversations you switched to with `/resume` or `/fork`.

What doesn't:

- Conversations you quit with <kbd>Ctrl</kbd>+<kbd>D</kbd> or replaced with
  `/new`.
- Pis that never got a reply, because they have no conversation on disk yet.
- Other programs; they come back as a plain shell.

pi-rex only acts on a server that started within the last two minutes, and once
per server instance. Reloading Rex's configuration later never types into a
running Pi.

## 🧰 Requirements

- Rex for macOS, version 0.1.0-preview.23 or later, which restores sessions
  across server restarts.
- `bash`, `awk`, and the `rex` CLI. The script finds the CLI inside the
  installed Rex app if it isn't on `PATH`.

## 🩺 Troubleshooting

The script logs what it did to `~/.local/state/pi-rex/log`. Records live next to
it, one file per block.

If a conversation didn't come back, check that the block had a reply before the
restart: `ls ~/.local/state/pi-rex`.

## 🧹 Uninstall

```sh
pi remove npm:pi-rex
```

Then remove the line from Rex's `init.lua`.

## 📄 License

[MIT](LICENSE)
