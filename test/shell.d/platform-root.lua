-- Test-only. base-test.sh runs this through LUA_INIT, which only the standalone
-- lua interpreter reads; Hyprland's embedded Lua never does, so nothing in a
-- desktop session's environment can move the platform root this way.
--
-- It points default.hypr.paths' platform root at OMARCHY_TEST_PLATFORM_ROOT, or
-- at a directory that doesn't exist, so a test never loads the platform files
-- installed on the machine running it. package.preload survives bootstrap.lua
-- clearing package.loaded, and the loader reads this checkout's paths.lua, not
-- whichever one package.path would find.

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$")

package.preload["default.hypr.paths"] = function()
  local paths = dofile(here .. "/../../default/hypr/paths.lua")
  local fixture = os.getenv("OMARCHY_TEST_PLATFORM_ROOT")
  if fixture == nil or fixture == "" then
    fixture = here .. "/no-platform-root"
  end
  paths.platform_root = fixture
  return paths
end
