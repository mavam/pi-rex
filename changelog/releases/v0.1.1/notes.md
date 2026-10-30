Pi Rex now waits for each block's shell prompt before reopening a conversation, so slow shell startups such as devenv no longer swallow the command.

## 🐞 Bug fixes

### Reliable resume after slow shell startups

Pi Rex now waits until each block's shell sits at its prompt before it reopens the conversation there. Previously, a slow shell startup, such as entering a devenv or direnv environment, could swallow the command, and the block came back as a plain shell.

Pi Rex also no longer types into a block where Pi or another program already runs, so reloading Rex's configuration right after a restart is safe. When Pi had moved its conversation to another directory, such as a worktree, Pi Rex changes there before reopening it.

*By @mavam.*
