-- rex-ladybird: open Ladybird's terminal browser in a Rex window or floating
-- layer.
--
-- Ladybird's --headless=terminal mode draws pages with the Kitty graphics
-- protocol and reads keyboard and mouse input from the terminal. Rex already
-- provides that terminal, so this plugin only launches it with a sane pixel
-- ratio and a label.

local M = {}

local SHELL_FLAVOR = "com.superlogical.terminal.shell"

local config = {
  binary = nil,
  device_pixel_ratio = "auto",
  extra_args = {},
  bind = true,
  keep_open = false,
  label = "ladybird",
  float_bounds = { 0.1, 0.1, 0.8, 0.75 },
}

local registered = false
local bound = false

local function log(level, message)
  if rex and rex.log then
    rex.log(level, "rex-ladybird: " .. message)
  end
end

local function expand_home(path)
  if type(path) ~= "string" then
    return nil
  end
  if path == "~" then
    return os.getenv("HOME")
  end
  if path:sub(1, 2) == "~/" then
    return (os.getenv("HOME") or "") .. path:sub(2)
  end
  return path
end

local function file_exists(path)
  local file = io.open(path, "rb")
  if file then
    file:close()
    return true
  end
  return false
end

local function app_binary(path)
  if path:sub(-4) == ".app" then
    return path .. "/Contents/MacOS/Ladybird"
  end
  return path
end

local function find_in_path(name)
  local path = os.getenv("PATH") or ""
  for dir in path:gmatch("[^:]+") do
    local candidate = dir .. "/" .. name
    if file_exists(candidate) then
      return candidate
    end
  end
  return nil
end

local function resolve_binary()
  local configured = config.binary or os.getenv("LADYBIRD_BIN")
  if configured ~= nil then
    if type(configured) ~= "string" or configured == "" then
      log("warn", "binary must be a non-empty string, ignoring it")
    else
      local expanded = expand_home(configured)
      if not expanded then
        return nil
      end
      if expanded:find("/", 1, true) then
        expanded = app_binary(expanded)
        if file_exists(expanded) then
          return expanded
        end
        return nil
      end
      return find_in_path(expanded)
    end
  end

  local home = os.getenv("HOME") or ""
  local candidates = {
    "/Applications/Ladybird.app/Contents/MacOS/Ladybird",
    home .. "/Applications/Ladybird.app/Contents/MacOS/Ladybird",
    "/usr/local/bin/ladybird",
    "/opt/homebrew/bin/ladybird",
    "/usr/bin/ladybird",
    home .. "/.local/bin/ladybird",
    "/snap/bin/ladybird",
  }
  for _, candidate in ipairs(candidates) do
    if file_exists(candidate) then
      return candidate
    end
  end
  return find_in_path("ladybird")
end

local function terminal_call(ctx, method, args)
  if not ctx or not ctx.session_id or not ctx.block_id then
    return nil, "no focused block"
  end
  return rex.call("block.method", {
    session_id = ctx.session_id,
    block_id = ctx.block_id,
    method = method,
    args = args or {},
  })
end

local function detect_device_pixel_ratio(ctx)
  local setting = config.device_pixel_ratio
  if type(setting) == "number" and setting > 0 then
    return setting
  end
  if type(setting) == "string" and setting ~= "auto" then
    local parsed = tonumber(setting)
    if parsed and parsed > 0 then
      return parsed
    end
    log("warn", "invalid device_pixel_ratio " .. setting .. ", using auto")
  end

  local size = terminal_call(ctx, "size", {})
  local cell_height = size and tonumber(size.cell_height_px)
  -- A Retina cell is roughly twice as tall in pixels as a 1x cell. If this
  -- guess is wrong for your font or display, set device_pixel_ratio in
  -- setup() and stop guessing.
  if cell_height and cell_height >= 24 then
    return 2
  end
  return 1
end

local function sanitize_url(text)
  if type(text) ~= "string" then
    return nil
  end
  text = text:gsub("%c", " ")
  text = text:gsub("%s+", " ")
  text = text:gsub("^%s+", "")
  text = text:gsub("%s+$", "")
  if text == "" then
    return nil
  end
  return text
end

local function build_command(url, device_pixel_ratio)
  local binary = resolve_binary()
  if not binary then
    return nil, "Ladybird was not found. Set LADYBIRD_BIN or binary in setup()."
  end

  local command = {
    binary,
    "--headless=terminal",
    "--device-pixel-ratio=" .. string.format("%g", device_pixel_ratio),
  }

  if type(config.extra_args) == "table" then
    for _, arg in ipairs(config.extra_args) do
      if type(arg) == "string" then
        table.insert(command, arg)
      end
    end
  end

  if url and url ~= "" then
    table.insert(command, url)
  end

  return command
end

local function layout_for(url, device_pixel_ratio)
  local command, err = build_command(url, device_pixel_ratio)
  if not command then
    return nil, err
  end

  local options = {
    shell = "none",
    command = command,
  }
  if config.keep_open then
    options.exit = { on_completion = false }
  end

  return rex.layout.block{
    flavor = SHELL_FLAVOR,
    label = config.label,
    options = options,
  }
end

local function open_browser(ctx, url, floating, device_pixel_ratio)
  url = sanitize_url(url)
  local ratio = tonumber(device_pixel_ratio)
  if not ratio or ratio <= 0 then
    ratio = detect_device_pixel_ratio(ctx)
  end

  local layout, err = layout_for(url, ratio)
  if not layout then
    log("error", err)
    return nil, err
  end

  local result
  if floating then
    result, err = rex.session.new_layer{
      bounds = {
        config.float_bounds[1],
        config.float_bounds[2],
        config.float_bounds[3],
        config.float_bounds[4],
      },
      focus = true,
      layout = layout,
    }
  else
    result, err = rex.session.new_window{
      window_label = "Ladybird",
      layout = layout,
    }
  end

  if not result then
    log("error", "could not open Ladybird: " .. tostring(err))
    return nil, err
  end
  return result
end

local function valid_bounds(bounds)
  if type(bounds) ~= "table" or #bounds ~= 4 then
    return false
  end
  for index = 1, 4 do
    local value = bounds[index]
    if type(value) ~= "number" or value < 0 or value > 1 then
      return false
    end
  end
  if bounds[3] <= 0 or bounds[4] <= 0 then
    return false
  end
  return bounds[1] + bounds[3] <= 1 and bounds[2] + bounds[4] <= 1
end

local function define_actions()
  rex.action{
    name = "ladybird_open",
    title = "Open Ladybird",
    description = "Open Ladybird's terminal browser in a new Rex window.",
    category = "Ladybird",
    keywords = "browser web ladybird open",
    args = { url = "string?", device_pixel_ratio = "number?" },
    run = function(ctx, args)
      args = args or {}
      return open_browser(ctx, args.url, false, args.device_pixel_ratio)
    end,
  }

  rex.action{
    name = "ladybird_float",
    title = "Open Ladybird Floating",
    description = "Open Ladybird in a floating layer over the active window.",
    category = "Ladybird",
    keywords = "browser web ladybird floating overlay",
    args = { url = "string?", device_pixel_ratio = "number?" },
    run = function(ctx, args)
      args = args or {}
      return open_browser(ctx, args.url, true, args.device_pixel_ratio)
    end,
  }
end

local function define_bindings()
  rex.bind("cmd+shift+l", "ladybird_open")
  rex.bind("cmd+shift+alt+l", "ladybird_float")
end

function M.setup(options)
  options = options or {}

  if options.binary ~= nil then
    config.binary = options.binary
  end
  if options.device_pixel_ratio ~= nil then
    config.device_pixel_ratio = options.device_pixel_ratio
  end
  if options.extra_args ~= nil then
    if type(options.extra_args) == "table" then
      config.extra_args = options.extra_args
    else
      log("warn", "extra_args must be a list, ignoring it")
    end
  end
  if options.bind ~= nil then
    config.bind = options.bind and true or false
  end
  if options.keep_open ~= nil then
    config.keep_open = options.keep_open and true or false
  end
  if options.label ~= nil then
    if type(options.label) == "string" and options.label ~= "" then
      config.label = options.label
    else
      log("warn", "label must be a non-empty string, ignoring it")
    end
  end
  if options.float_bounds ~= nil then
    if valid_bounds(options.float_bounds) then
      config.float_bounds = {
        options.float_bounds[1],
        options.float_bounds[2],
        options.float_bounds[3],
        options.float_bounds[4],
      }
    else
      log("warn", "float_bounds must be four fractions that fit inside [0, 1], ignoring it")
    end
  end

  if not registered then
    define_actions()
    registered = true
  end

  if config.bind and not bound then
    define_bindings()
    bound = true
  end
end

function M.open(ctx, url, floating, device_pixel_ratio)
  return open_browser(ctx, url, floating and true or false, device_pixel_ratio)
end

function M.binary()
  return resolve_binary()
end

-- rexd loads this file as a plugin's config code. Rex's own config loads it
-- through require() and calls setup() itself.
if rexd and rexd.plugin then
  M.setup()
end

return M
