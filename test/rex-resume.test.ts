import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { chmodSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

const bin = (name: string) => new URL(`../bin/${name}`, import.meta.url).pathname;
const harness = new URL("rex-resume.lua", import.meta.url).pathname;

// Rex runs Lua 5.1; LuaJIT implements the same language.
const lua = ["luajit", "lua5.1", "lua"].find((command) => spawnSync(command, ["-v"]).status === 0);
assert.ok(lua, "the tests need a Lua interpreter, such as luajit");

const names = execFileSync(lua, [harness, bin("rex-resume.lua"), "--list"], { encoding: "utf8" })
  .trim()
  .split("\n");
for (const name of names) {
  test(name, () => {
    const run = spawnSync(lua, [harness, bin("rex-resume.lua"), name], { encoding: "utf8" });
    assert.equal(run.status, 0, run.stderr);
  });
}

test("the wrapper runs the Lua script once the server answers", () => {
  const dir = mkdtempSync(join(tmpdir(), "rex-resume-"));
  writeFileSync(
    join(dir, "rex"),
    `#!/bin/sh
[ "$1" = --autostart=false ] || exit 64
shift
case "$1" in
  server) exit 0 ;;
  do) printf '%s\\n' "$2" > "${dir}/ran" ;;
  *) exit 64 ;;
esac
`,
  );
  chmodSync(join(dir, "rex"), 0o755);
  execFileSync("bash", [bin("rex-resume")], {
    env: { PATH: `${dir}:/usr/bin:/bin`, HOME: dir, XDG_STATE_HOME: join(dir, "state") },
  });
  assert.equal(readFileSync(join(dir, "ran"), "utf8"), `${bin("rex-resume.lua")}\n`);
});
