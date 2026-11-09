---------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------
local HOST                  = "127.0.0.1"  -- localhost only: nobody else on the network can connect
local PORT                  = 7777
local POLL_INTERVAL_SECONDS = 1            -- how often we check the socket
local MAX_LINES_PER_POLL    = 100          -- safety cap so a flood of commands can't freeze the sim
local SCRIPT_PATH           = lfs.writedir() .. [[Missions\dcs-control\dcs_socket_bridge.lua]]

---------------------------------------------------------------------
-- Reload support
---------------------------------------------------------------------
BRIDGE = BRIDGE or {}
BRIDGE.generation = BRIDGE.generation or 0
if BRIDGE.stop then BRIDGE.stop() end
BRIDGE.generation = BRIDGE.generation + 1
local generation = BRIDGE.generation

---------------------------------------------------------------------
-- Load LuaSocket
---------------------------------------------------------------------
if not package.path:find("LuaSocket", 1, true) then   -- only add the folder once
  package.path  = package.path  .. ";" .. lfs.currentdir() .. "\\LuaSocket\\?.lua"
  package.cpath = package.cpath .. ";" .. lfs.currentdir() .. "\\LuaSocket\\?.dll"
end
local socket = require("socket")

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function announce(message)
  trigger.action.outText("[bridge] " .. message, 5)
  env.info("[bridge] " .. message)
end

-- Open the listening socket. Timeout 0 = never block the sim waiting for data.
local listener = assert(socket.bind(HOST, PORT))
listener:settimeout(0)
announce("listening on " .. HOST .. ":" .. PORT)

local connection   = nil   -- the connected Python client, or nil
local pending_text = ""    -- text received so far that is not yet a complete line

local function close_connection()
  if connection then pcall(connection.close, connection) end
  connection, pending_text = nil, ""
end

local function run_command(code)
  local chunk, compile_err = loadstring(code)
  if not chunk then
    env.error("[bridge] compile: " .. tostring(compile_err))
    return
  end
  local ok, run_err = pcall(chunk)
  if not ok then
    env.error("[bridge] runtime: " .. tostring(run_err))
  end
end

---------------------------------------------------------------------
-- Public functions (callable from Python via lua("BRIDGE...."))
---------------------------------------------------------------------
BRIDGE.say = announce

BRIDGE.reload = function()
  local chunk, compile_err = loadfile(SCRIPT_PATH)
  if not chunk then
    announce("reload FAILED (compile): " .. tostring(compile_err))
    return
  end
  announce("reloading...")
  local ok, run_err = pcall(chunk)         -- the new copy calls BRIDGE.stop() on this one
  if not ok then announce("reload FAILED (runtime): " .. tostring(run_err)) end
end

---------------------------------------------------------------------
-- Poll loop: runs once per POLL_INTERVAL_SECONDS
---------------------------------------------------------------------
local function poll(_, now)

  if BRIDGE.generation ~= generation then return nil end

  local new_connection = listener:accept()
  if new_connection then
    if connection then
      close_connection()
      announce("previous connection replaced")
    end
    connection = new_connection
    connection:settimeout(0)
    announce("Python connected")
  end


  if connection then
    for _ = 1, MAX_LINES_PER_POLL do
      local line, recv_err, partial_text = connection:receive("*l")
      pending_text = pending_text .. (line or partial_text or "")

      if line then
        run_command(pending_text)
        pending_text = ""
        if BRIDGE.generation ~= generation then return nil end
      elseif recv_err ~= "timeout" then
        close_connection()
        announce("Python disconnected (" .. tostring(recv_err) .. ") - waiting for reconnect")
        break
      else
        break
      end
    end
  end

  return now + POLL_INTERVAL_SECONDS
end

timer.scheduleFunction(poll, nil, timer.getTime() + 1)