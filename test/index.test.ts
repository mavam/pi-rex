import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import extension, { stateDir } from "../src/index.ts";

type Handler = (event: unknown, ctx: unknown) => unknown;

const root = mkdtempSync(join(tmpdir(), "pi-rex-"));
process.env.XDG_STATE_HOME = join(root, "state");
process.env.REX_BLOCK = "block:abc";

const sessionFile = join(root, "session.jsonl");
const ctx = {
  sessionManager: {
    getSessionFile: () => sessionFile,
    getSessionId: () => "01a18979-333d",
    getCwd: () => "/work/tree",
  },
};
const record = join(stateDir(), "block:abc");

function load() {
  const handlers = new Map<string, Handler>();
  extension({ on: (name: string, handler: Handler) => handlers.set(name, handler) } as never);
  return { handlers };
}

test("waits for the session file before recording", async () => {
  const { handlers } = load();
  await handlers.get("session_start")!({}, ctx);
  assert.equal(existsSync(record), false);
  writeFileSync(sessionFile, "");
  await handlers.get("agent_end")!({}, ctx);
  assert.equal(readFileSync(record, "utf8"), "01a18979-333d\n/work/tree\n");
});

test("keeps the record across reloads and conversation switches", async () => {
  const { handlers } = load();
  for (const reason of ["reload", "resume", "fork"]) {
    await handlers.get("session_shutdown")!({ reason }, ctx);
    assert.equal(existsSync(record), true, reason);
  }
});

test("removes the record for a new conversation", async () => {
  const { handlers } = load();
  await handlers.get("agent_end")!({}, ctx);
  await handlers.get("session_shutdown")!({ reason: "new" }, ctx);
  assert.equal(existsSync(record), false);
});

test("removes the record when the user quits", async () => {
  const { handlers } = load();
  await handlers.get("agent_end")!({}, ctx);
  await handlers.get("session_shutdown")!({ reason: "quit" }, ctx);
  assert.equal(existsSync(record), false);
});

test("keeps the record when the terminal hangs up", async () => {
  const { handlers } = load();
  await handlers.get("session_start")!({}, ctx);
  await handlers.get("agent_end")!({}, ctx);
  // Pi's own handler starts the shutdown before the hangup flag is set.
  const shutdown = handlers.get("session_shutdown")!({ reason: "quit" }, ctx);
  process.emit("SIGHUP");
  await shutdown;
  assert.equal(existsSync(record), true);
});

test("installs the resume scripts at a stable path", async () => {
  const { handlers } = load();
  await handlers.get("session_start")!({}, ctx);
  for (const name of ["rex-resume", "rex-resume.lua"]) {
    const source = new URL(`../bin/${name}`, import.meta.url).pathname;
    const target = join(stateDir(), name);
    assert.equal(readFileSync(target, "utf8"), readFileSync(source, "utf8"));
    assert.ok(statSync(target).mode & 0o100, "executable");

    // An outdated copy, as left by an earlier version, is replaced.
    writeFileSync(target, "old");
    await handlers.get("session_start")!({}, ctx);
    assert.equal(readFileSync(target, "utf8"), readFileSync(source, "utf8"));
  }
});

test("installs the script but records nothing outside Rex", async () => {
  delete process.env.REX_BLOCK;
  rmSync(record, { force: true });
  const { handlers } = load();
  assert.deepEqual([...handlers.keys()], ["session_start"]);
  await handlers.get("session_start")!({}, ctx);
  assert.equal(existsSync(record), false);
  assert.equal(existsSync(join(stateDir(), "rex-resume.lua")), true);
});
