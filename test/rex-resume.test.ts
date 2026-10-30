import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

const script = new URL("../bin/rex-resume", import.meta.url).pathname;
const instance = "c0e24309-2693-4eaa-a728-034480ae02fb";
const block = "block:01a18988-8263-75ff-887d-8713287563c4";
const session = "session:01a18988-8249-7979-b6af-5afab60e5667";
const id = "01a18979-333d-70d1-a704-915e5dda7102";

const timestamp = (secondsAgo: number) =>
  new Date(Date.now() - secondsAgo * 1000).toISOString().replace(/\.\d+Z$/, "Z");

/** A throwaway Rex server: a fake `rex` on PATH answering from files. */
function setup(options: { startedAgo?: number; failSessions?: boolean } = {}) {
  const dir = mkdtempSync(join(tmpdir(), "rex-resume-"));
  const fake = join(dir, "fake");
  const state = join(dir, "state", "pi-rex");
  mkdirSync(fake);
  mkdirSync(state, { recursive: true });
  writeFileSync(
    join(fake, "rex"),
    `#!/bin/sh
[ "$1" = --autostart=false ] || exit 64
shift
case "$1 $2" in
  "server status") printf 'instance: %s\\nstarted: %s\\n' "${instance}" "${timestamp(options.startedAgo ?? 5)}" ;;
  "session ls") ${options.failSessions ? "exit 1" : `echo "${session}"`} ;;
  "block ls") echo "${block}" ;;
  "send "*) printf '%s\\n' "$*" >> "${dir}/sent" ;;
  *) exit 64 ;;
esac
`,
  );
  chmodSync(join(fake, "rex"), 0o755);
  const run = () =>
    execFileSync("bash", [script], {
      env: {
        PATH: `${fake}:/usr/bin:/bin`,
        HOME: dir,
        XDG_STATE_HOME: join(dir, "state"),
      },
      stdio: "pipe",
    });
  const sent = () => (existsSync(join(dir, "sent")) ? readFileSync(join(dir, "sent"), "utf8") : "");
  const log = () => readFileSync(join(state, "log"), "utf8");
  return { state, run, sent, log };
}

test("resumes the recorded conversation in its block", () => {
  const { state, run, sent, log } = setup();
  writeFileSync(join(state, block), `${id}\n`);
  run();
  assert.equal(sent(), `send -s ${session} -b ${block} pi --session ${id}\r\n`);
  assert.match(log(), /resumed block:01a18988-8263-.* with pi session 01a18979-/);
  assert.equal(readFileSync(join(state, "instance"), "utf8"), `${instance}\n`);
});

test("drops records of blocks that no longer exist or are malformed", () => {
  const { state, run, sent, log } = setup();
  writeFileSync(join(state, "block:gone"), `${id}\n`);
  writeFileSync(join(state, block), "not an id\n");
  run();
  assert.equal(sent(), "");
  assert.equal(existsSync(join(state, "block:gone")), false);
  assert.equal(existsSync(join(state, block)), false);
  assert.match(log(), /dropped malformed record/);
});

test("does nothing when the server is older than two minutes", () => {
  const { state, run, sent } = setup({ startedAgo: 600 });
  writeFileSync(join(state, block), `${id}\n`);
  run();
  assert.equal(sent(), "");
  assert.equal(existsSync(join(state, "instance")), false);
});

test("resumes once per server instance", () => {
  const { state, run, sent } = setup();
  writeFileSync(join(state, block), `${id}\n`);
  run();
  run();
  assert.equal(sent(), `send -s ${session} -b ${block} pi --session ${id}\r\n`);
});

test("keeps the records when Rex cannot list its sessions", () => {
  const { state, run, sent } = setup({ failSessions: true });
  writeFileSync(join(state, block), `${id}\n`);
  assert.throws(run);
  assert.equal(existsSync(join(state, block)), true);
  assert.equal(existsSync(join(state, "instance")), false);
  assert.equal(sent(), "");
});

test("handles an empty state directory", () => {
  const { run, sent } = setup();
  run();
  assert.equal(sent(), "");
});
