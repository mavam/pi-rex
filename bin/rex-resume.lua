-- Reopen the Pi conversations that ran in Rex blocks before the server stopped.
-- Rex restores sessions, tabs, and block IDs but not their programs. The pi-rex
-- extension records each block's conversation in a file named after the block:
-- the session ID, then the session's working directory.

local state = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/pi-rex"
local max_age = tonumber(os.getenv("PI_REX_MAX_AGE") or "") or 120
local patience = tonumber(os.getenv("PI_REX_PATIENCE") or "") or 120
local interval = 0.5
-- Shell startup can run programs that take over the terminal and discard what
-- they read, such as devenv's task runner, so a block must sit at its prompt
-- this long before we type into it.
local settle = 2
-- How long Pi gets to start after we typed the command.
local launch = 15

local function log(message)
  local file = io.open(state .. "/log", "a")
  if file then
    file:write(os.date("!%Y-%m-%dT%H:%M:%SZ "), message, "\n")
    file:close()
  end
end

local function read(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local text = file:read("*a")
  file:close()
  return text
end

local function call(method, args)
  local result, err = rex.call(method, args)
  if result == nil then error(method .. ": " .. tostring(err), 0) end
  return result
end

-- Seconds since the epoch for an RFC 3339 UTC timestamp, independent of the
-- local time zone.
local function epoch(timestamp)
  local y, m, d, hh, mm, ss = timestamp:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if m <= 2 then y = y - 1 end
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local doy = math.floor((153 * ((m + 9) % 12) + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return (era * 146097 + doe - 719468) * 86400 + tonumber(hh) * 3600 + tonumber(mm) * 60 + tonumber(ss)
end

-- Single quotes that fish and POSIX shells read the same way.
local function quote(text)
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

-- A freshly started server has lost its programs; a config reload runs init
-- again and must not touch a server whose blocks are already in use.
local status = call("server.status")
if os.time() - epoch(status.started_at) > max_age then return end
if read(state .. "/instance") == status.instance_id .. "\n" then return end

-- Wait for Rex to restore its sessions, then map each block to its session.
local sessions
for _ = 1, 60 do
  sessions = call("session.list").sessions
  if #sessions > 0 then break end
  rex.sleep(interval)
end
if #sessions == 0 then return end
local session_of = {}
for _, session in ipairs(sessions) do
  call("session.attach", { session_id = session.session_id })
  for _, block in ipairs(call("session.list_blocks", { session_id = session.session_id }).blocks) do
    session_of[block.block_id] = session.session_id
  end
end
local marker = assert(io.open(state .. "/instance", "w"))
marker:write(status.instance_id, "\n")
marker:close()

local function method(block, name, args)
  return rex.call("block.method", {
    session_id = session_of[block],
    block_id = block,
    method = name,
    args = args,
  })
end

-- What runs in the block: "prompt" when its shell waits for input, "pi" when
-- Pi runs, "busy" otherwise, or nil when Rex can't tell. For a prompt, also
-- the shell's process.
local function activity(block)
  local process = method(block, "process", {})
  local mode = method(block, "input_mode", {})
  if not process or not process.foreground or not mode then return nil end
  local foreground = process.foreground
  if foreground.argv0 == "pi" or foreground.name == "pi" then return "pi" end
  -- The terminal's own process is the shell, or login running it on macOS.
  local child = process.child or {}
  local ancestors = process.ancestors or {}
  local top = foreground.pid == child.pid or (#ancestors == 1 and child.name == "login")
  -- A shell's line editor reads keys one at a time without echo.
  if top and not mode.canonical then return "prompt", foreground end
  return "busy"
end

local pending = {}
local listing = rex.exec({ "ls", "-1", state })
for name in ((listing and listing.stdout) or ""):gmatch("[^\n]+") do
  if name:match("^block:") then
    local path = state .. "/" .. name
    local id, cwd = (read(path) or ""):match("^([^\n]*)\n?([^\n]*)")
    if not session_of[name] then
      os.remove(path)
    elseif not id or not id:match("^[%x-]+$") then
      log("dropped malformed record for " .. name)
      os.remove(path)
    else
      pending[name] = { id = id, cwd = cwd ~= "" and cwd or nil }
    end
  end
end

local deadline = os.time() + patience
while next(pending) and os.time() < deadline do
  for block, entry in pairs(pending) do
    local now = os.time()
    local seen, shell = activity(block)
    if entry.sent then
      if seen == "pi" or seen == "busy" then
        log("resumed " .. block .. " with pi session " .. entry.id)
        pending[block] = nil
      elseif now - entry.sent > launch then
        log("pi didn't start in " .. block)
        pending[block] = nil
      end
    elseif seen == "pi" then
      log("left " .. block .. " alone, pi already runs there")
      pending[block] = nil
    elseif seen == "prompt" and entry.since and entry.pid == shell.pid then
      if now - entry.since >= settle then
        local command = "pi --session " .. entry.id
        -- Pi may have moved its session to another directory, such as a
        -- worktree, while the shell stayed behind.
        if entry.cwd and entry.cwd ~= shell.cwd then
          command = "cd " .. quote(entry.cwd) .. " && " .. command
        end
        method(block, "write", { data = command .. "\r" })
        entry.sent = now
      end
    else
      entry.since, entry.pid = now, shell and shell.pid
    end
  end
  if next(pending) then rex.sleep(interval) end
end
for block in pairs(pending) do
  log("gave up on " .. block .. ", its shell never sat at a prompt")
end

for _, session in ipairs(sessions) do
  rex.call("session.detach", { session_id = session.session_id })
end
