import { chmodSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const bin = fileURLToPath(new URL("../bin/", import.meta.url));
const scripts = ["rex-resume", "rex-resume.lua"];

/** Where records live, one file per Rex block with its Pi session ID and directory. */
export function stateDir(env: NodeJS.ProcessEnv = process.env): string {
  return join(env.XDG_STATE_HOME || join(homedir(), ".local", "state"), "pi-rex");
}

/** Copy the scripts from the package to their stable paths unless current. */
function install() {
  for (const name of scripts) {
    try {
      const source = readFileSync(join(bin, name));
      const target = join(stateDir(), name);
      if (existsSync(target) && readFileSync(target).equals(source)) continue;
      mkdirSync(stateDir(), { recursive: true, mode: 0o700 });
      const tmp = `${target}.${process.pid}`;
      writeFileSync(tmp, source, { mode: 0o755 });
      chmodSync(tmp, 0o755);
      renameSync(tmp, target);
    } catch {
      // Installing must never disturb the session.
    }
  }
}

// Set when the terminal hangs up, which is what a Rex server stop does. It
// lives on globalThis because every runtime reload creates a new instance of
// the extension, but the process signal listeners must be registered once.
const state = globalThis as unknown as { __piRexHungUp?: boolean };

export default function (pi: ExtensionAPI) {
  // Outside Rex, there is nothing to record.
  const block = process.env.REX_BLOCK;
  const recording = block && !/[^\w:.-]/.test(block) && !block.startsWith(".");
  const dir = stateDir();
  const file = join(dir, block ?? "");

  const record = (ctx: ExtensionContext) => {
    try {
      // Pi writes the session file with the first reply; resuming needs it.
      const session = ctx.sessionManager.getSessionFile();
      if (!session || !existsSync(session)) return;
      mkdirSync(dir, { recursive: true, mode: 0o700 });
      const tmp = join(dir, `.${block}.${process.pid}`);
      writeFileSync(tmp, `${ctx.sessionManager.getSessionId()}\n${ctx.sessionManager.getCwd()}\n`);
      renameSync(tmp, file);
    } catch {
      // Recording must never disturb the session.
    }
  };

  pi.on("session_start", (_event, ctx) => {
    install();
    if (!recording) return;
    if (state.__piRexHungUp === undefined) {
      state.__piRexHungUp = false;
      for (const signal of ["SIGHUP", "SIGTERM"] as const) {
        process.once(signal, () => (state.__piRexHungUp = true));
      }
    }
    record(ctx);
  });

  if (!recording) return;

  pi.on("agent_end", (_event, ctx) => record(ctx));

  pi.on("session_shutdown", async (event) => {
    // Pi's own signal handler starts the shutdown before ours has run.
    await new Promise((resolve) => setImmediate(resolve));
    // A new conversation replaces the recorded one, and quitting means the user
    // is done with it; a hangup means the server stopped under it.
    if (event.reason === "new" || (event.reason === "quit" && !state.__piRexHungUp)) {
      rmSync(file, { force: true });
    }
  });
}
