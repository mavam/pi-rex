-- Runs bin/rex-resume.lua against a fake Rex server.
-- Usage: lua test/rex-resume.lua SCRIPT [--list | NAME]

local script, which = arg[1], arg[2]
local unpack = unpack or table.unpack
local real_time, real_getenv = os.time, os.getenv
local tests, order = {}, {}

local function test(name, fn)
  tests[name] = fn
  order[#order + 1] = name
end

local function read(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local text = file:read("*a")
  file:close()
  return text
end

local function write(path, text)
  local file = assert(io.open(path, "w"))
  file:write(text)
  file:close()
end

local function iso(seconds)
  return os.date("!%Y-%m-%dT%H:%M:%S.000000Z", seconds)
end

-- Blocks behave over time: each returns what runs in it, given the seconds
-- since the script started and when the script typed into it.
local function idle(cwd)
  return function(_, sent) return sent and "pi" or "prompt", cwd end
end
local function starting(seconds)
  return function(elapsed, sent)
    if sent then return "pi" end
    return elapsed < seconds and "busy" or "prompt"
  end
end
local function running(kind)
  return function() return kind end
end
local function stuck()
  return function() return "prompt" end
end

-- Runs the script in a fresh state directory and returns what happened.
local function run(options)
  local dir = os.tmpname()
  os.remove(dir)
  os.execute("mkdir -p '" .. dir .. "/pi-rex'")
  local state = dir .. "/pi-rex"
  for name, text in pairs(options.records or {}) do write(state .. "/" .. name, text) end
  if options.marker then write(state .. "/instance", options.marker .. "\n") end

  local start = 1800000000
  local clock = start
  local writes, sent = {}, {}
  local blocks = options.blocks or {}
  local env = {
    XDG_STATE_HOME = dir,
    PI_REX_MAX_AGE = options.max_age,
    PI_REX_PATIENCE = options.patience or 30,
  }

  os.time = function(t) if t then return real_time(t) end return math.floor(clock) end
  os.getenv = function(name)
    if env[name] ~= nil then return tostring(env[name]) end
    return real_getenv(name)
  end
  rex = {
    sleep = function(seconds) clock = clock + seconds end,
    exec = function(argv)
      local pipe = io.popen("ls -1 '" .. argv[3] .. "'")
      local out = pipe:read("*a")
      pipe:close()
      return { ok = true, stdout = out }
    end,
    call = function(method, args)
      if method == "server.status" then
        return { instance_id = "instance", started_at = iso(start - (options.started_ago or 5)) }
      elseif method == "session.list" then
        if options.fail_list then return nil, "boom" end
        return { sessions = { { session_id = "session:s", label = "work" } } }
      elseif method == "session.list_blocks" then
        local list = {}
        for block in pairs(blocks) do list[#list + 1] = { block_id = block } end
        return { blocks = list }
      elseif method == "session.attach" or method == "session.detach" then
        return {}
      elseif method == "block.method" then
        local block = args.block_id
        local kind, cwd = blocks[block](clock - start, sent[block])
        if args.method == "write" then
          writes[#writes + 1] = { block = block, data = args.args.data, at = clock - start }
          sent[block] = true
          return { bytes_written = #args.args.data }
        elseif args.method == "input_mode" then
          -- devenv's task runner reads keys raw too; only the process tree tells.
          return { canonical = false, echo = false }
        elseif args.method == "process" then
          -- On macOS, the terminal runs login, which runs the shell; on Linux,
          -- the terminal runs the shell itself.
          local shell = { pid = 10, name = "fish", argv0 = "-fish", cwd = cwd or "/home" }
          local child = options.linux and shell or { pid = 5, name = "login" }
          local above = options.linux and {} or { child }
          local function under(...)
            local chain = { unpack(above) }
            for _, process in ipairs({ ... }) do chain[#chain + 1] = process end
            return chain
          end
          if kind == "prompt" then
            return { child = child, foreground = shell, ancestors = above }
          elseif kind == "pi" then
            return { child = child, foreground = { pid = 30, name = "node", argv0 = "pi" }, ancestors = under(shell) }
          else
            return { child = child, foreground = { pid = 20, name = "devenv", argv0 = "devenv" }, ancestors = under(shell) }
          end
        end
      end
      error("unexpected call " .. method)
    end,
  }

  local ok, err = pcall(dofile, script)
  os.time, os.getenv = real_time, real_getenv
  local files = {}
  local pipe = io.popen("ls -1 '" .. state .. "'")
  for name in pipe:read("*a"):gmatch("[^\n]+") do files[name] = true end
  pipe:close()
  local result = {
    ok = ok,
    err = err,
    writes = writes,
    log = read(state .. "/log") or "",
    marker = read(state .. "/instance"),
    exists = function(name) return files[name] == true end,
  }
  os.execute("rm -rf '" .. dir .. "'")
  return result
end

local function check(condition, message)
  if not condition then error(message, 2) end
end

local id = "01a18979-333d-70d1-a704-915e5dda7102"

test("resumes a conversation once its shell settles at the prompt", function()
  local r = run({ blocks = { ["block:a"] = idle("/home") }, records = { ["block:a"] = id .. "\n/home\n" } })
  check(r.ok, tostring(r.err))
  check(#r.writes == 1, "expected one write, got " .. #r.writes)
  check(r.writes[1].data == "pi --session " .. id .. "\r", r.writes[1].data)
  check(r.writes[1].at >= 2, "typed before the prompt settled")
  check(r.log:find("resumed block:a with pi session " .. id, 1, true), r.log)
  check(r.marker == "instance\n", "marker not written")
end)

test("resumes where the terminal runs the shell itself", function()
  local r = run({ linux = true, blocks = { ["block:a"] = starting(4) }, records = { ["block:a"] = id .. "\n" } })
  check(#r.writes == 1 and r.writes[1].at >= 6, "expected one write after the startup")
end)

test("waits until a slow shell startup reaches the prompt", function()
  local r = run({ blocks = { ["block:a"] = starting(10) }, records = { ["block:a"] = id .. "\n" } })
  check(#r.writes == 1, "expected one write, got " .. #r.writes)
  check(r.writes[1].at >= 12, "typed during startup at " .. r.writes[1].at)
end)

test("changes to the session's directory when the shell is elsewhere", function()
  local r = run({ blocks = { ["block:a"] = idle("/home") }, records = { ["block:a"] = id .. "\n/work/it's\n" } })
  check(r.writes[1].data == "cd '/work/it'\\''s' && pi --session " .. id .. "\r", r.writes[1].data)
end)

test("accepts records without a directory", function()
  local r = run({ blocks = { ["block:a"] = idle("/home") }, records = { ["block:a"] = id } })
  check(r.writes[1].data == "pi --session " .. id .. "\r", r.writes[1].data)
end)

test("leaves a block alone where pi already runs", function()
  local r = run({ blocks = { ["block:a"] = running("pi") }, records = { ["block:a"] = id .. "\n" } })
  check(#r.writes == 0, "typed into a running pi")
  check(r.log:find("left block:a alone", 1, true), r.log)
  check(r.exists("block:a"), "record removed")
end)

test("gives up on a block whose shell never reaches the prompt", function()
  local r = run({ patience = 5, blocks = { ["block:a"] = running("busy") }, records = { ["block:a"] = id .. "\n" } })
  check(r.ok, tostring(r.err))
  check(#r.writes == 0, "typed into a busy block")
  check(r.log:find("gave up on block:a", 1, true), r.log)
end)

test("reports when pi doesn't start", function()
  local r = run({ blocks = { ["block:a"] = stuck() }, records = { ["block:a"] = id .. "\n" } })
  check(#r.writes == 1, "expected one write")
  check(r.log:find("pi didn't start in block:a", 1, true), r.log)
end)

test("drops records of missing blocks and malformed records", function()
  local r = run({
    blocks = { ["block:a"] = idle() },
    records = { ["block:a"] = "not an id\n", ["block:gone"] = id .. "\n" },
  })
  check(#r.writes == 0, "typed a malformed record")
  check(not r.exists("block:a") and not r.exists("block:gone"), "records kept")
  check(r.log:find("dropped malformed record for block:a", 1, true), r.log)
end)

test("ignores a server that started long ago", function()
  local r = run({ started_ago = 600, blocks = { ["block:a"] = idle() }, records = { ["block:a"] = id .. "\n" } })
  check(#r.writes == 0 and r.marker == nil, "acted on an old server")
end)

test("resumes once per server instance", function()
  local r = run({ marker = "instance", blocks = { ["block:a"] = idle() }, records = { ["block:a"] = id .. "\n" } })
  check(#r.writes == 0, "resumed twice")
end)

test("keeps the records when Rex can't list its sessions", function()
  local r = run({ fail_list = true, blocks = { ["block:a"] = idle() }, records = { ["block:a"] = id .. "\n" } })
  check(not r.ok, "succeeded without sessions")
  check(r.exists("block:a") and r.marker == nil, "records or marker changed")
end)

if which == "--list" then
  for _, name in ipairs(order) do print(name) end
else
  local fn = assert(tests[which], "no test named " .. tostring(which))
  fn()
end
