---
title: Reopen Pi conversations after Rex restarts
type: feature
authors:
  - mavam
created: 2026-10-30T06:56:14.405783Z
---

Pi Rex reopens your Pi conversations in Rex terminal blocks after the Rex server restarts. Rex restores sessions, tabs, splits, and working directories on its own; Pi Rex adds the one missing piece, the conversation that ran in each block.

Each Pi records its conversation in the block it runs in. The extension installs a small resume script at `~/.local/state/pi-rex/rex-resume`; add two lines to Rex's `init.lua` to run it when the server starts. When the server restarts, the script types `pi --session <id>` into every block that had a recorded conversation, so you continue in the same block and directory.

Quitting Pi or starting a `/new` conversation forgets the block, so only conversations that were still open when the server stopped or crashed come back.
