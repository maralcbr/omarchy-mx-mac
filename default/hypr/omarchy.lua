-- Omarchy Hyprland setup: helpers, defaults, and current theme overrides.

require("default.hypr.helpers")
local platform = require("default.hypr.platform")
local require_optional = require("default.hypr.require_optional")

-- A platform package's binds (hypr/defaults/*.lua under the platform root),
-- loaded before Omarchy's so that a chord they bind replaces Omarchy's default
-- for it and the user's files can override both. See o.platform_chords in
-- helpers.lua.
o.binding_phase = "platform"
platform.load("defaults")
o.binding_phase = "defaults"

-- Use Omarchy defaults, but don't edit these directly.
require("default.hypr.autostart")
if _G.omarchy_default_bindings ~= false then
  require("default.hypr.bindings.media")
  require("default.hypr.bindings.clipboard")
  require("default.hypr.bindings.tiling")
  require("default.hypr.bindings.utilities")
  require("default.hypr.bindings.voxtype")
  require_optional.module("default.hypr.bindings.applications")
end
o.binding_phase = nil
require("default.hypr.envs")
require("default.hypr.looknfeel")
require("default.hypr.qconsole")
require("default.hypr.monitor-removal")
require("default.hypr.input")
require("default.hypr.windows")

-- A platform package's settings (hypr/settings/*.lua), loaded
-- after Omarchy's defaults so they replace them, and before the theme and the
-- user's files so those replace theirs. Anything a user sets globally belongs
-- in hl.config there: Hyprland reads a device's own hl.device value ahead of
-- the global one whatever the load order, so the user's global setting
-- couldn't replace it. hl.device is for what applies to that device alone.
platform.load("settings")

-- Current theme overrides.
require_optional.module("omarchy.current.theme.hyprland")
