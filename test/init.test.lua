-- Unit tests for init.lua.
--
-- Run from the repository root with:
--   lua5.1 test/init.test.lua
--
-- The test replaces the global rex table with a small stub before loading the
-- plugin, so it does not need a running Rex server.

local function assert_equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 2)
  end
end

local function assert_truthy(value, label)
  if not value then
    error(label .. ": expected a truthy value", 2)
  end
end

local actions = {}
local action_order = {}
local bindings = {}
local logs = {}
local last_window
local last_layer

rex = {
  action = function(definition)
    actions[definition.name] = definition
    table.insert(action_order, definition.name)
  end,
  bind = function(key, name)
    bindings[key] = name
  end,
  log = function(level, message)
    table.insert(logs, { level = level, message = message })
  end,
  layout = {
    block = function(definition)
      return { block = definition }
    end,
  },
  session = {
    new_window = function(args)
      last_window = args
      return { block_ids = { "block:window" }, window_id = "window:1", revision = 1 }
    end,
    new_layer = function(args)
      last_layer = args
      return { block_ids = { "block:float" }, layer_id = "layer:1", revision = 1 }
    end,
  },
  call = function(method, args)
    if method == "block.method" and args.method == "size" then
      return { cell_height_px = 32 }
    end
    return nil, "unexpected call"
  end,
}

local function load_plugin()
  local chunk, err = loadfile("init.lua")
  if not chunk then
    error("run this from the repository root: " .. tostring(err))
  end
  return chunk()
end

local plugin = load_plugin()
plugin.setup{ binary = "/bin/sh" }

assert_equal(#action_order, 2, "action count")
assert_equal(actions.ladybird_open.title, "Open Ladybird", "open title")
assert_equal(actions.ladybird_float.title, "Open Ladybird Floating", "float title")
assert_equal(actions.ladybird_open.category, "Ladybird", "open category")
assert_equal(bindings["cmd+shift+l"], "ladybird_open", "open binding")
assert_equal(bindings["cmd+shift+alt+l"], "ladybird_float", "float binding")

local ctx = { session_id = "session:1", block_id = "block:1" }

-- A normal open uses the auto pixel ratio and passes the URL through.
local result = assert(plugin.open(ctx, "https://example.com", false))
assert_equal(result.window_id, "window:1", "window result")
assert_equal(last_window.window_label, "Ladybird", "window label")
assert_equal(last_window.layout.block.label, "ladybird", "block label")
assert_equal(last_window.layout.block.options.shell, "none", "shell")
local command = last_window.layout.block.options.command
assert_equal(command[1], "/bin/sh", "binary")
assert_equal(command[2], "--headless=terminal", "headless argument")
assert_equal(command[3], "--device-pixel-ratio=2", "auto pixel ratio")
assert_equal(command[#command], "https://example.com", "url argument")

-- A floating open uses the default bounds.
assert(plugin.open(ctx, nil, true))
assert_equal(last_layer.bounds[1], 0.1, "float x")
assert_equal(last_layer.bounds[2], 0.1, "float y")
assert_equal(last_layer.bounds[3], 0.8, "float width")
assert_equal(last_layer.bounds[4], 0.75, "float height")
assert_equal(last_layer.focus, true, "float focus")

-- Bounds are configurable, and an explicit pixel ratio wins.
plugin.setup{ float_bounds = { 0.2, 0.15, 0.6, 0.7 } }
assert(plugin.open(ctx, nil, true, 1))
assert_equal(last_layer.bounds[1], 0.2, "custom float x")
assert_equal(last_layer.bounds[3], 0.6, "custom float width")
assert_equal(last_layer.layout.block.options.command[3], "--device-pixel-ratio=1", "pinned pixel ratio")

-- Invalid bounds warn and leave the previous bounds alone.
plugin.setup{ float_bounds = { 0.9, 0.9, 0.4, 0.4 } }
assert(plugin.open(ctx, nil, true, 1))
assert_equal(last_layer.bounds[3], 0.6, "invalid bounds ignored")
local warned = false
for _, entry in ipairs(logs) do
  if string.find(entry.message, "float_bounds", 1, true) then
    warned = true
  end
end
assert_truthy(warned, "invalid bounds warning")

-- Control characters in a URL are made harmless.
assert(plugin.open(ctx, " https://example.com\nnext ", false, 1))
local sanitized = last_window.layout.block.options.command
assert_equal(sanitized[#sanitized], "https://example.com next", "url sanitized")

-- A missing binary is reported without opening a block.
local missing = load_plugin()
missing.setup{ binary = "/definitely/not/a/ladybird" }
local ok, err = missing.open(ctx, nil, false, 1)
assert_equal(ok, nil, "missing binary result")
assert_truthy(string.find(err, "not found", 1, true), "missing binary error")

print("ok")
