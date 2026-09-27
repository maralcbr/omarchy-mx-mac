-- Loads a platform package's own Hyprland defaults from hypr/<slot> under the
-- platform root (/usr/share/omarchy-platform). Omarchy ships none. Each file is
-- loaded by its path, so it can't shadow a module, and on its own, so one that
-- fails is reported and the rest of the config still loads.

local paths = require("default.hypr.paths")

local M = {}

local root = paths.platform_root .. "/hypr"

local function shell_quote(path)
  return "'" .. path:gsub("'", "'\\''") .. "'"
end

-- Lua can't add to Hyprland's config error bar, so a failure goes to the log and
-- a notification. Reporting must never stop the config either.
function M.report(message)
  pcall(function()
    io.stderr:write(message .. "\n")
    hl.notification.create({ text = message, duration = 15000, icon = "error" })
  end)
end

-- Loads hypr/<slot>/*.lua (defaults, settings or gestures) in byte order,
-- whatever the session's locale. Symlinks are followed, as the other platform
-- readers follow them: a packaged file or the slot directory itself may be
-- one. A dangling one is skipped.
function M.load(slot)
  local dir = root .. "/" .. slot
  local handle = io.popen("find -L " .. shell_quote(dir) .. " -maxdepth 1 -type f -name '*.lua' -printf '%f\\n' 2>/dev/null | LC_ALL=C sort")
  if not handle then
    return
  end

  local files = {}
  for filename in handle:lines() do
    table.insert(files, dir .. "/" .. filename)
  end
  handle:close()

  for _, file in ipairs(files) do
    local chunk, err = loadfile(file)
    local ok = chunk ~= nil
    if ok then
      ok, err = pcall(chunk)
    end
    if not ok then
      M.report("Omarchy skipped a platform default that failed: " .. tostring(err))
    end
  end
end

return M
