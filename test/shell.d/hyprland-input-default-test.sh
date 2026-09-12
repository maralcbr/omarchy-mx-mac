#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"
require_command lua
lua - "$ROOT" <<'LUA'
local root = arg[1]
local devices = {}
local config
hl = {
  config = function(value) config = value end,
  device = function(value) devices[value.name] = value end,
}
o = { window = function() end }
dofile(root .. "/default/hypr/input.lua")
assert(config.input.touchpad.tap_to_click == nil, "no global tap override")
assert(config.input.touchpad.natural_scroll == false, "traditional scrolling")
assert(devices["apple-mtp-multi-touch"].tap_to_click == false, "Apple tap disabled")
local count = 0
for _ in pairs(devices) do count = count + 1 end
assert(count == 1, "only Apple device is overridden")
local user = assert(io.open(root .. "/config/hypr/input.lua")):read("*a")
local override = assert(user:match("%-%- (hl%.device%([^\n]+)"), "documented override")
assert(load(override))()
assert(devices["apple-mtp-multi-touch"].tap_to_click == true, "user override wins")
LUA
pass "Apple-only touchpad default and documented user override"
