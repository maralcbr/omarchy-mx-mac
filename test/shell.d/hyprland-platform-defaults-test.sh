#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

# Hyprland loads a platform package's gestures from hypr/gestures under the
# platform root (/usr/share/omarchy-platform), after the user's files, so the
# user's settings can keep them out. The fixture below is such a default: a
# three-finger sideways workspace swipe that steps aside for a gesture the user
# set. base-test.sh points the standalone lua interpreter at a fixture root
# through OMARCHY_TEST_PLATFORM_ROOT (test/shell.d/platform-root.lua).

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

no_platform="$tmpdir/no-platform"
gestures="$tmpdir/gestures"
mkdir -p "$gestures/hypr/gestures"
cat >"$gestures/hypr/gestures/fixture-gesture.lua" <<'LUA'
if _G.fixture_gesture == false then
  return
end
for _, gesture in ipairs(o.registered_gestures or {}) do
  if gesture.fingers == 3 and not gesture.modified and (gesture.direction == "horizontal" or gesture.direction == "left" or gesture.direction == "right" or gesture.direction == "swipe") then
    return
  end
end
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
LUA

# Loads the shipped hyprland.lua against a user's ~/.config/hypr and prints one
# line per gesture Hyprland accepted, then "error" for each one it rejected.
# The stub applies Hyprland 0.56's rule (CTrackpadGestures::addGesture): a
# gesture on the same fingers and mods is refused once an earlier one covers
# its direction or axis, and the refusal is a config error.
load_config() {
  local edit="${1:-}" omarchy_path="${OMARCHY_UNDER_TEST:-$ROOT}" platform_root="${PLATFORM_UNDER_TEST:-$gestures}"
  local home
  home=$(mktemp -d "$tmpdir/home.XXXXXX")

  mkdir -p "$home/.config"
  cp -R "$ROOT/config/hypr" "$home/.config/hypr"
  [[ -z $edit ]] || printf '%s\n' "$edit" >>"$home/.config/hypr/input.lua"
  if [[ -n ${THEME_EDIT:-} ]]; then
    mkdir -p "$home/.local/state/omarchy/current/theme"
    printf '%s\n' "$THEME_EDIT" >"$home/.local/state/omarchy/current/theme/hyprland.lua"
  fi

  HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" OMARCHY_PATH="$omarchy_path" OMARCHY_TEST_PLATFORM_ROOT="$platform_root" \
    lua <<'LUA'
local function proxy()
  return setmetatable({}, {
    __index = function(self, key)
      local value = proxy()
      rawset(self, key, value)
      return value
    end,
    __call = function()
      return {}
    end,
  })
end

-- CTrackpadGestures::dirForString and the axes addGesture compares.
local aliases = {
  l = "left", r = "right", u = "up", t = "up", top = "up", d = "down", b = "down", bottom = "down",
  horiz = "horizontal", vert = "vertical", zoomin = "pinchin", zoomout = "pinchout",
}
local axes = {
  left = "horizontal", right = "horizontal", horizontal = "horizontal",
  up = "vertical", down = "vertical", vertical = "vertical",
  swipe = "swipe", pinch = "pinch", pinchin = "pinch", pinchout = "pinch",
}
local accepted = {}
local scroll_factor

-- KeybindManager::stringToModMask: any string naming no modifier is mask zero.
local function mod_mask(mods)
  local mask = {}
  mods = (mods or ""):upper()
  for name, bit in pairs({ SHIFT = "S", CAPS = "C", CTRL = "T", CONTROL = "T", ALT = "A", SUPER = "M", WIN = "M", META = "M" }) do
    if mods:find(name, 1, true) then
      mask[bit] = true
    end
  end
  local bits = {}
  for bit in pairs(mask) do
    table.insert(bits, bit)
  end
  table.sort(bits)
  return table.concat(bits)
end

hl = setmetatable({
  dsp = proxy(),
  gesture = function(gesture)
    local direction = gesture.direction:lower()
    direction = aliases[direction] or direction
    local axis = axes[direction]
    local mods = mod_mask(gesture.mods)

    -- hlGesture refuses fingers that aren't an integer from 2 to 9 and an
    -- action it doesn't know, and an unset takes away the gesture it names.
    local known = { workspace = true, move = true, close = true, unset = true }
    if math.type(gesture.fingers) ~= "integer" or gesture.fingers < 2 or gesture.fingers > 9 or
      (type(gesture.action) == "string" and not known[gesture.action]) then
      print("error")
      return
    end
    if gesture.action == "unset" then
      for index, g in ipairs(accepted) do
        if g.fingers == gesture.fingers and g.direction == direction and g.mods == mods then
          table.remove(accepted, index)
          print("unset " .. gesture.fingers .. " " .. direction)
          return
        end
      end
      print("error")
      return
    end

    for _, g in ipairs(accepted) do
      if g.fingers == gesture.fingers and g.mods == mods and
        (g.direction == axis or g.direction == direction or
          ((axis == "horizontal" or axis == "vertical") and g.direction == "swipe")) then
        print("error")
        return
      end
    end

    table.insert(accepted, { fingers = gesture.fingers, direction = direction, mods = mods })
    local action = type(gesture.action) == "string" and gesture.action or "function"
    print(gesture.fingers .. " " .. direction .. " " .. (mods ~= "" and "+" .. mods .. " " or "") .. action)
  end,
  config = function(values)
    local touchpad = type(values.input) == "table" and values.input.touchpad
    if type(touchpad) == "table" and touchpad.scroll_factor ~= nil then
      scroll_factor = touchpad.scroll_factor
    end
  end,
  notification = {
    create = function(notification)
      print("notify\t" .. notification.text)
    end,
  },
  get_config = function() return nil end,
  get_active_window = function() return nil end,
  get_monitors = function() return {} end,
}, {
  __index = function()
    return function()
      return {}
    end
  end,
})

dofile(os.getenv("HOME") .. "/.config/hypr/hyprland.lua")
if os.getenv("SHOW_SCROLL") then
  print("scroll " .. tostring(scroll_factor))
end
LUA
}

swipe="3 horizontal workspace"

# Hyprland's embedded Lua reads no LUA_INIT, so the root it sees is paths.lua's
# own, whatever the environment says; lua -E runs without LUA_INIT as Hyprland
# does. Under the test seam, an unset fixture root points at nothing.
platform_root_of() {
  lua "$@" - <<'LUA'
package.path = os.getenv("ROOT") .. "/?.lua;" .. package.path
print(require("default.hypr.paths").platform_root)
LUA
}
production=$(OMARCHY_PATH="$gestures" OMARCHY_TEST_PLATFORM_ROOT="$gestures" OMARCHY_PACKAGED_PATH="$gestures" \
  OMARCHY_PLATFORM_ROOT="$gestures" platform_root_of -E)
[[ $production == /usr/share/omarchy-platform ]] || fail "no environment variable moves the platform root" "$production"
[[ $(platform_root_of) == "$ROOT/test/shell.d/no-platform-root" && ! -e $ROOT/test/shell.d/no-platform-root ]] ||
  fail "under the test seam, no fixture means no platform root" "$(platform_root_of)"
! grep -rlF --exclude-dir=.git --exclude="$(basename "${BASH_SOURCE[0]}")" OMARCHY_PACKAGED_PATH "$ROOT" ||
  fail "nothing reads OMARCHY_PACKAGED_PATH"
pass "the platform root is fixed, and tests see only their fixture"

[[ -z $(PLATFORM_UNDER_TEST=$no_platform load_config) ]] || fail "without a platform package there is no default gesture" "$(PLATFORM_UNDER_TEST=$no_platform load_config)"
pass "without a platform package, Omarchy adds no gesture"

# OMARCHY_PATH stays this checkout, as in a development setup, while the
# platform package's file sits only in the platform root.
[[ $(load_config) == "$swipe" ]] || fail "a platform package's gesture loads from the platform root" "$(load_config)"
pass "a platform package's gestures load from the platform root, whatever OMARCHY_PATH points at"

output=$(load_config 'hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })')
[[ $output == "$swipe" ]] || fail "the user's own gesture keeps the platform's out" "$output"
output=$(load_config 'hl.gesture({ fingers = 3, direction = "left", action = function() end })')
[[ $output == "3 left function" ]] || fail "a user gesture on the same axis keeps the platform's out" "$output"
# The registry records a direction by Hyprland's full name, whatever the user
# wrote, so the fixture only has to name those.
for direction in l R Horiz swipe; do
  output=$(load_config 'hl.gesture({ fingers = 3, direction = "'"$direction"'", action = "workspace" })')
  expected="3 $(tr '[:upper:]' '[:lower:]' <<<"$direction" | sed 's/^l$/left/; s/^r$/right/; s/^horiz$/horizontal/') workspace"
  [[ $output == "$expected" ]] || fail "a user gesture spelled $direction keeps the platform's out" "$output"
done
for direction in vertical u pinch; do
  output=$(load_config 'hl.gesture({ fingers = 3, direction = "'"$direction"'", action = "close" })')
  [[ $(tail -n 1 <<<"$output") == "$swipe" ]] || fail "a user gesture spelled $direction leaves the platform's in" "$output"
done
output=$(load_config 'hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })')
[[ $output == $'4 horizontal workspace
'"$swipe" ]] || fail "a gesture on other fingers keeps the platform's" "$output"
output=$(load_config 'hl.gesture({ fingers = 3, direction = "horizontal", mods = "SUPER", action = "move" })')
[[ $output == $'3 horizontal +M move
'"$swipe" ]] || fail "a gesture held with a modifier keeps the platform's" "$output"
for mods in '"NONE"' '""'; do
  output=$(load_config 'hl.gesture({ fingers = 3, direction = "horizontal", mods = '"$mods"', action = "workspace" })')
  [[ $output == "$swipe" ]] || fail "mods = $mods counts as no modifier" "$output"
done
pass "platform defaults load after the user's files and see the user's gestures"

# A user gesture Hyprland refuses doesn't count: hl.gesture tells Lua nothing
# of a refusal, so the registry predicts it, and the platform's default stays.
for refused in 'action = "wrokspace"' 'action = "workspace", fingers = 3.0' 'action = "workspace", fingers = "3"'; do
  output=$(load_config 'hl.gesture({ fingers = 3, direction = "horizontal", '"$refused"' })')
  [[ $output == $'error\n'"$swipe" ]] || fail "a refused user gesture ($refused) leaves the platform's in" "$output"
done
output=$(load_config 'hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "horizontal", action = "unset" })')
[[ $output == $'3 horizontal workspace\nunset 3 horizontal\n'"$swipe" ]] || fail "a gesture the user unset leaves the platform's in" "$output"
pass "only gestures Hyprland keeps make a platform default step aside"

# The prediction, case by case, against the checks Hyprland 0.56 makes
# (hlGesture, CTrackpadGestures::addGesture and removeGesture).
ROOT="$ROOT" lua - <<'LUA' || fail "the gesture registry predicts Hyprland 0.56's verdicts"
package.path = os.getenv("ROOT") .. "/?.lua;" .. package.path
local registry = require("default.hypr.gesture-registry")
local f = function() end
local failed = false
local function expect(wanted, registered, gesture, label)
  local ok, change = pcall(registry.verdict, registered, gesture)
  local got = ok and (change or "refuse") or ("raise: " .. tostring(change))
  if got ~= wanted then
    failed = true
    io.stderr:write("not ok - " .. label .. ": wanted " .. wanted .. ", got " .. got .. "\n")
  end
end
local function record(gesture)
  local change, value = registry.verdict({}, gesture)
  assert(change == "add", "fixture gesture is accepted")
  return value
end

for label, gesture in pairs({
  ["a named action"] = { fingers = 3, direction = "horizontal", action = "workspace" },
  ["a short direction in any case"] = { fingers = 3, direction = "L", action = f },
  ["a callback table"] = { fingers = 3, direction = "swipe", action = { start = f } },
  ["every callback"] = { fingers = 3, direction = "swipe", action = { start = f, update = f, finish = f } },
  ["modifiers"] = { fingers = 4, direction = "up", action = "close", mods = "SUPER" },
  ["a numeric mods string"] = { fingers = 3, direction = "left", action = "move", mods = 5 },
  ["a scale in a string"] = { fingers = 3, direction = "left", action = "move", scale = "1.5" },
  ["a scale of true"] = { fingers = 3, direction = "left", action = "move", scale = true },
  ["a scale of 10"] = { fingers = 3, direction = "left", action = "move", scale = 10 },
  ["a scale of 0.11"] = { fingers = 3, direction = "left", action = "move", scale = 0.11 },
  ["disable_inhibit as 1"] = { fingers = 3, direction = "left", action = "move", disable_inhibit = 1 },
  ["string options on a callback"] = { fingers = 3, direction = "left", action = f, mode = "toggle", zoom_level = 2 },
}) do
  expect("add", {}, gesture, "accepts " .. label)
end

for label, gesture in pairs({
  ["no table"] = "horizontal",
  ["float fingers"] = { fingers = 3.0, direction = "left", action = "move" },
  ["string fingers"] = { fingers = "3", direction = "left", action = "move" },
  ["boolean fingers"] = { fingers = true, direction = "left", action = "move" },
  ["one finger"] = { fingers = 1, direction = "left", action = "move" },
  ["ten fingers"] = { fingers = 10, direction = "left", action = "move" },
  ["no direction"] = { fingers = 3, action = "move" },
  ["an unknown direction"] = { fingers = 3, direction = "sideways", action = "move" },
  ["a numeric direction"] = { fingers = 3, direction = 3, action = "move" },
  ["no action"] = { fingers = 3, direction = "left" },
  ["an unknown action"] = { fingers = 3, direction = "left", action = "wrokspace" },
  ["a numeric action"] = { fingers = 3, direction = "left", action = 3 },
  ["an empty callback table"] = { fingers = 3, direction = "left", action = {} },
  ["a callback that isn't a function"] = { fingers = 3, direction = "left", action = { start = f, update = "x" } },
  ["a table option"] = { fingers = 3, direction = "left", action = f, zoom_level = {} },
  ["boolean mods"] = { fingers = 3, direction = "left", action = "move", mods = true },
  ["a scale of false"] = { fingers = 3, direction = "left", action = "move", scale = false },
  ["a scale below 0.1"] = { fingers = 3, direction = "left", action = "move", scale = 0.05 },
  ["a scale above 10"] = { fingers = 3, direction = "left", action = "move", scale = 11 },
  -- Hyprland compares the number against its bounds as C floats: 0.1F is a
  -- little more than 0.1, and 10.0000001 is more than 10F before it's rounded.
  ["a scale of 0.1"] = { fingers = 3, direction = "left", action = "move", scale = 0.1 },
  ["a scale just above 10"] = { fingers = 3, direction = "left", action = "move", scale = 10.0000001 },
  ["a scale that isn't a number"] = { fingers = 3, direction = "left", action = "move", scale = "abc" },
  ["disable_inhibit as 2"] = { fingers = 3, direction = "left", action = "move", disable_inhibit = 2 },
  ["disable_inhibit as a word"] = { fingers = 3, direction = "left", action = "move", disable_inhibit = "yes" },
}) do
  expect("refuse", {}, gesture, "refuses " .. label)
end

local horizontal = record({ fingers = 3, direction = "horizontal", action = "workspace" })
local swipe = record({ fingers = 3, direction = "swipe", action = "workspace" })
local up = record({ fingers = 3, direction = "up", action = "close" })
local left = record({ fingers = 3, direction = "left", action = "close" })
local pinch = record({ fingers = 3, direction = "pinch", action = "close" })
expect("refuse", { horizontal }, { fingers = 3, direction = "left", action = "move" }, "an axis covers its directions")
expect("add", { left }, { fingers = 3, direction = "horizontal", action = "move" }, "a direction doesn't cover its axis")
expect("refuse", { swipe }, { fingers = 3, direction = "up", action = "move" }, "a swipe covers up and down")
expect("refuse", { swipe }, { fingers = 3, direction = "swipe", action = "move" }, "a swipe covers a swipe")
expect("add", { up }, { fingers = 3, direction = "swipe", action = "move" }, "up doesn't cover a swipe")
expect("refuse", { pinch }, { fingers = 3, direction = "zoomin", action = "move" }, "a pinch covers pinching in")
expect("add", { swipe }, { fingers = 3, direction = "pinch", action = "move" }, "a swipe doesn't cover a pinch")
expect("add", { horizontal }, { fingers = 4, direction = "left", action = "move" }, "other fingers are free")
expect("add", { horizontal }, { fingers = 3, direction = "left", action = "move", mods = "SUPER" }, "other modifiers are free")
expect("refuse", { record({ fingers = 3, direction = "left", action = "move", mods = "SUPER" }) },
  { fingers = 3, direction = "left", action = "move", mods = "WIN" }, "SUPER and WIN are one modifier")
expect("refuse", { horizontal }, { fingers = 3, direction = "left", action = "move", mods = "NONE" }, "NONE is no modifier, so the unmodified gesture covers it")

expect("remove", { horizontal }, { fingers = 3, direction = "horiz", action = "unset" }, "an unset takes out the gesture it names")
expect("refuse", { horizontal }, { fingers = 3, direction = "left", action = "unset" }, "an unset needs the exact direction")
expect("refuse", { horizontal }, { fingers = 3, direction = "horizontal", action = "unset", mods = "SUPER" }, "an unset needs the exact modifiers")
expect("refuse", { horizontal }, { fingers = 3, direction = "horizontal", action = "unset", scale = 2 }, "an unset needs the exact scale")
expect("remove", { record({ fingers = 3, direction = "left", action = "move", scale = 1.1 }) },
  { fingers = 3, direction = "left", action = "unset", scale = "1.1" }, "an unset compares scales as Hyprland stores them")
expect("refuse", {}, { fingers = 3, direction = "left", action = "unset" }, "an unset of nothing is refused")
os.exit(failed and 1 or 0)
LUA
pass "the gesture registry predicts Hyprland 0.56's verdicts"

output=$(load_config 'fixture_gesture = false')
[[ -z $output ]] || fail "a setting in the user's files reaches the platform defaults" "$output"
pass "a setting in the user's files reaches the platform defaults"

# ── early defaults: binds ────────────────────────────────────────────────────

# A platform package's early defaults (hypr/defaults) load
# before Omarchy's. This fixture binds a chord Omarchy leaves free, takes over
# one Omarchy binds, and decorates menu binds with a bind that must run first,
# picking them by the command they run even when they reach the shell through
# its global shortcut.
early="$tmpdir/early"
mkdir -p "$early/hypr/defaults"
cat >"$early/hypr/defaults/fixture-binds.lua" <<'LUA'
if _G.omarchy_default_bindings ~= false then
  o.bind("SUPER + F12", "Platform screenshot", "platform-screenshot")
  o.bind("shift + XF86MonBrightnessUp", "Platform brightness", "platform-brightness")
end
table.insert(o.bind_decorators, function(keys, dispatcher, opts, command)
  if type(command) == "string" and command:find("^omarchy%-menu") then
    -- A decorator that binds through o.bind is not decorated again.
    o.bind("TWIN + " .. keys, "Platform menu twin", dispatcher)
    hl.bind(keys, "platform-focus", {})
  end
end)
LUA

# Prints one line per bind Hyprland ends up with, in the order they run:
# keys, then the command (or "platform-focus").
load_binds() {
  local edit="${1:-}" platform_root="${PLATFORM_UNDER_TEST:-$early}" top="${2:-}" user_module="${3:-}"
  local home
  home=$(mktemp -d "$tmpdir/home.XXXXXX")

  mkdir -p "$home/.config"
  cp -R "$ROOT/config/hypr" "$home/.config/hypr"
  [[ -z $edit ]] || printf '%s\n' "$edit" >>"$home/.config/hypr/bindings.lua"
  [[ -z $top ]] || printf '%s\n%s\n' "$top" "$(cat "$home/.config/hypr/hyprland.lua")" >"$home/.config/hypr/hyprland.lua"
  [[ -z $user_module ]] || printf '%s\n' "$user_module" >"$home/.config/extra.lua"

  HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.local/state" OMARCHY_PATH="$ROOT" OMARCHY_TEST_PLATFORM_ROOT="$platform_root" \
    lua <<'LUA'
local function proxy()
  return setmetatable({}, {
    __index = function(self, key)
      local value = proxy()
      rawset(self, key, value)
      return value
    end,
    __call = function()
      return {}
    end,
  })
end

local binds = {}
hl = setmetatable({
  dsp = setmetatable({
    exec_cmd = function(cmd) return { cmd = cmd } end,
    global = function(name) return { cmd = "global " .. name } end,
  }, { __index = function() return proxy() end }),
  bind = function(keys, dispatcher, opts)
    -- Only commands and decorator markers are compared; other dispatchers
    -- print by kind, not by their (per-run) address.
    local command = type(dispatcher) == "table" and dispatcher.cmd or type(dispatcher) == "string" and dispatcher or type(dispatcher)
    table.insert(binds, { keys = keys, command = command })
  end,
  -- Hyprland parses a chord into a modifier mask and a key, so spelling and
  -- modifier order don't matter to unbind.
  unbind = function(keys)
    local function parsed(value)
      local parts = {}
      for raw in (value .. "+"):gmatch("([^+]*)%+") do
        local part = raw:match("^%s*(.-)%s*$"):upper()
        if part ~= "" then table.insert(parts, part) end
      end
      local key = table.remove(parts) or ""
      table.sort(parts)
      return table.concat(parts, "+") .. "+" .. key
    end
    for index = #binds, 1, -1 do
      if parsed(binds[index].keys) == parsed(keys) then
        table.remove(binds, index)
      end
    end
  end,
  notification = {
    create = function(notification)
      if os.getenv("NOTIFY_THROWS") then
        error("no notification overlay")
      end
      print("notify\t" .. notification.text)
    end,
  },
  get_config = function() return nil end,
  get_active_window = function() return nil end,
  get_monitors = function() return {} end,
}, {
  __index = function()
    return function()
      return {}
    end
  end,
})

dofile(os.getenv("HOME") .. "/.config/hypr/hyprland.lua")
for _, bind in ipairs(binds) do
  print(bind.keys .. "\t" .. tostring(bind.command))
end
LUA
}

plain=$(PLATFORM_UNDER_TEST=$no_platform load_binds) || fail "bindings load without a platform package" "$plain"
grep -qxF $'SHIFT + XF86MonBrightnessUp\tomarchy-brightness-display 100%' <<<"$plain" ||
  fail "without a platform package Omarchy's default binds as before" "$plain"
! grep -q 'platform-' <<<"$plain" || fail "without a platform package nothing platform binds" "$plain"
pass "without a platform package the default bindings are as before"

binds=$(load_binds) || fail "bindings load with platform defaults" "$binds"
grep -qxF $'SUPER + F12\tplatform-screenshot' <<<"$binds" || fail "a platform default binds a free chord" "$binds"
[[ $(grep -ci '^SHIFT + XF86MonBrightnessUp' <<<"$binds") == 1 ]] && grep -qxF $'shift + XF86MonBrightnessUp\tplatform-brightness' <<<"$binds" ||
  fail "a platform default replaces Omarchy's default for the same chord, however it is spelled" "$binds"
diff <(grep -v -e 'platform-' -e '^TWIN + ' <<<"$binds") <(grep -v '^SHIFT + XF86MonBrightnessUp' <<<"$plain") >"$tmpdir/bind-diff" ||
  fail "every other default bind is unchanged, in the same order" "$(cat "$tmpdir/bind-diff")"
pass "a platform's early defaults bind free chords and replace Omarchy's default for theirs"

[[ $(grep -A1 -xF $'SUPER + SPACE\tplatform-focus' <<<"$binds" | tail -n 1) == $'SUPER + SPACE\tglobal omarchy:menu.root' ]] ||
  fail "a decorator's bind runs right before the bind it decorates" "$binds"
! grep -qxF $'SUPER + RETURN\tplatform-focus' <<<"$binds" || fail "a decorator leaves other binds alone"
grep -qxF $'TWIN + SUPER + SPACE\tglobal omarchy:menu.root' <<<"$binds" && ! grep -qF 'TWIN + TWIN' <<<"$binds" ||
  fail "a bind a decorator makes through o.bind is not decorated again" "$binds"
pass "a platform decorator binds what must run first, right before the binds it picks"

user=$(load_binds 'o.rebind("SHIFT + XF86MonBrightnessUp", "Mine", "my-brightness")
hl.unbind("SUPER + F12")
o.bind("SUPER + ALT + M", "My menu", "omarchy-menu toggle")
o.bind("SUPER + ALT + N", "My route", { menu = "not-a-shortcut" })') || fail "user bindings load" "$user"
grep -qxF $'SHIFT + XF86MonBrightnessUp\tmy-brightness' <<<"$user" && ! grep -q 'platform-brightness' <<<"$user" ||
  fail "the user's rebind replaces the platform's" "$user"
! grep -q '^SUPER + F12' <<<"$user" || fail "the user can unbind a platform chord" "$user"
[[ $(grep -A1 -xF $'SUPER + ALT + M\tplatform-focus' <<<"$user" | tail -n 1) == $'SUPER + ALT + M\tomarchy-menu toggle' ]] ||
  fail "the user's own menu binds are decorated too" "$user"
[[ $(grep -A1 -xF $'SUPER + ALT + N\tplatform-focus' <<<"$user" | tail -n 1) == $'SUPER + ALT + N\tomarchy-menu toggle \'not-a-shortcut\'' ]] ||
  fail "a menu route the shell registers no shortcut for runs its command and is decorated" "$user"
pass "the user's files override platform defaults, and their binds are decorated too"

off=$(load_binds '' 'omarchy_default_bindings = false') || fail "bindings load with defaults off" "$off"
! grep -qE 'platform-(screenshot|brightness)|omarchy-brightness-display 100%' <<<"$off" ||
  fail "with default bindings off neither Omarchy's nor the platform's binds are made" "$off"
pass "with default bindings off, a platform file that honors it binds nothing"

# ── settings ─────────────────────────────────────────────────────────────────

# A platform package's settings (hypr/settings) load after
# Omarchy's defaults and before the theme and the user's files.
settings="$tmpdir/settings"
mkdir -p "$settings/hypr/settings"
cat >"$settings/hypr/settings/fixture-settings.lua" <<'LUA'
hl.config({ input = { touchpad = { scroll_factor = 0.25 } } })
o.bind("SUPER + F9", "Platform settings bind", "platform-settings")
LUA

scroll() {
  printf 'hl.config({ input = { touchpad = { scroll_factor = %s } } })' "$1"
}
[[ $(SHOW_SCROLL=1 PLATFORM_UNDER_TEST=$no_platform load_config) == "scroll 0.4" ]] || fail "Omarchy's default applies without a platform package"
output=$(SHOW_SCROLL=1 PLATFORM_UNDER_TEST=$settings load_config)
[[ $output == "scroll 0.25" ]] || fail "a platform setting replaces Omarchy's default" "$output"
output=$(SHOW_SCROLL=1 PLATFORM_UNDER_TEST=$settings THEME_EDIT="$(scroll 0.5)" load_config)
[[ $output == "scroll 0.5" ]] || fail "the theme replaces a platform setting" "$output"
output=$(SHOW_SCROLL=1 PLATFORM_UNDER_TEST=$settings load_config "$(scroll 0.6)")
[[ $output == "scroll 0.6" ]] || fail "the user's input.lua replaces a platform setting" "$output"
pass "platform settings replace Omarchy's defaults, and the theme and the user's files replace them"

output=$(PLATFORM_UNDER_TEST=$settings load_binds)
grep -qxF $'SUPER + F9\tplatform-settings' <<<"$output" || fail "a platform settings file can bind" "$output"
output=$(PLATFORM_UNDER_TEST=$settings load_binds 'hl.unbind("SUPER + F9")')
! grep -q '^SUPER + F9' <<<"$output" || fail "the user can unbind a bind a platform settings file made" "$output"
pass "the user's bindings.lua can unbind what a platform settings file bound"

# ── containment ──────────────────────────────────────────────────────────────

# A platform file that fails, to load or to run, is reported and skipped: the
# files after it, Omarchy's defaults and the user's files still load.
broken="$tmpdir/broken"
mkdir -p "$broken/hypr/defaults" "$broken/hypr/settings" "$broken/hypr/gestures"
printf '%s\n' 'error("early boom")' >"$broken/hypr/defaults/0-runtime.lua"
printf '%s\n' 'o.bind("SUPER + F12",' >"$broken/hypr/defaults/1-syntax.lua"
printf '%s\n' 'o.bind("SUPER + F12", "Platform screenshot", "platform-screenshot")' >"$broken/hypr/defaults/2-fine.lua"
printf '%s\n' 'error("settings boom")' >"$broken/hypr/settings/0-runtime.lua"
printf '%s\n' 'o.bind("SUPER + F9", "Platform settings bind", "platform-settings")' >"$broken/hypr/settings/1-fine.lua"
printf '%s\n' 'error("late boom")' >"$broken/hypr/gestures/0-runtime.lua"
printf '%s\n' 'o.bind("SUPER + F8", "Platform late marker", "platform-late")' >"$broken/hypr/gestures/1-fine.lua"

for notify in works throws; do
  output=$(PLATFORM_UNDER_TEST=$broken NOTIFY_THROWS=$([[ $notify == throws ]] && echo 1) \
    load_binds 'o.bind("SUPER + ALT + M", "Mine", "my-command")' 2>"$tmpdir/stderr") ||
    fail "the config loads past broken platform files (notification $notify)" "$output"
  for bind in $'SUPER + F12\tplatform-screenshot' $'SUPER + F9\tplatform-settings' $'SUPER + F8\tplatform-late' \
    $'SHIFT + XF86MonBrightnessUp\tomarchy-brightness-display 100%' $'SUPER + ALT + M\tmy-command'; do
    grep -qxF "$bind" <<<"$output" || fail "a broken platform file stops nothing else (notification $notify): $bind" "$output"
  done
  [[ $(grep -c 'Omarchy skipped a platform default that failed' "$tmpdir/stderr") == 4 ]] ||
    fail "each broken platform file is logged (notification $notify)" "$(cat "$tmpdir/stderr")"
done
notices=$(grep '^notify' <<<"$(PLATFORM_UNDER_TEST=$broken load_binds 2>/dev/null)")
for reason in 'early boom' '1-syntax.lua' 'settings boom' 'late boom'; do
  grep -qF "$reason" <<<"$notices" || fail "each broken platform file is shown: $reason" "$notices"
done
pass "a broken platform file is reported and the rest of the config still loads"

# A decorator that fails is reported once and turned off: every bind is still
# made, and the decorators after it still run.
decorators="$tmpdir/decorators"
mkdir -p "$decorators/hypr/defaults"
cat >"$decorators/hypr/defaults/fixture-decorators.lua" <<'LUA'
table.insert(o.bind_decorators, function()
  error("decorator boom")
end)
table.insert(o.bind_decorators, function(keys, dispatcher, opts, command)
  if type(command) == "string" and command:find("^omarchy%-menu") then
    hl.bind(keys, "platform-focus", {})
  end
end)
LUA
output=$(PLATFORM_UNDER_TEST=$decorators load_binds 'o.bind("SUPER + ALT + M", "My menu", "omarchy-menu toggle")' 2>/dev/null) ||
  fail "bindings load past a failing decorator" "$output"
diff <(grep -v -e '^notify' -e 'platform-focus' -e '^SUPER + ALT + M' <<<"$output") <(printf '%s\n' "$plain") >"$tmpdir/bind-diff" ||
  fail "a failing decorator stops no bind" "$(cat "$tmpdir/bind-diff")"
[[ $(grep -A1 -xF $'SUPER + SPACE\tplatform-focus' <<<"$output" | tail -n 1) == $'SUPER + SPACE\tglobal omarchy:menu.root' ]] &&
  [[ $(grep -A1 -xF $'SUPER + ALT + M\tplatform-focus' <<<"$output" | tail -n 1) == $'SUPER + ALT + M\tomarchy-menu toggle' ]] ||
  fail "the decorators after a failing one still run" "$output"
[[ $(grep -c '^notify.*decorator boom' <<<"$output") == 1 ]] || fail "a failing decorator is reported once" "$output"
pass "a failing decorator is reported once and every bind is still made"

# Platform files load by path: one named like a module the user requires
# doesn't take its place.
shadow="$tmpdir/shadow"
mkdir -p "$shadow/hypr/defaults"
printf '%s\n' 'o.bind("SUPER + F7", "Platform extra", "platform-extra")' >"$shadow/hypr/defaults/extra.lua"
output=$(PLATFORM_UNDER_TEST=$shadow load_binds 'require("extra")' '' 'o.bind("SUPER + F6", "Mine", "user-extra")')
grep -qxF $'SUPER + F7\tplatform-extra' <<<"$output" && grep -qxF $'SUPER + F6\tuser-extra' <<<"$output" ||
  fail "a platform file named like the user's module shadows neither" "$output"
pass "a platform file can't shadow a module"

# A packaged file or a slot directory may be a symlink, as the other platform
# readers allow; a dangling one is skipped quietly. Files load in byte order
# whatever the session's locale.
linked="$tmpdir/linked"
elsewhere="$tmpdir/elsewhere"
mkdir -p "$linked/hypr/defaults" "$elsewhere/settings"
printf '%s\n' 'o.bind("SUPER + F5", "Platform linked", "platform-linked")' >"$elsewhere/linked.lua"
ln -s "$elsewhere/linked.lua" "$linked/hypr/defaults/linked.lua"
ln -s "$elsewhere/missing.lua" "$linked/hypr/defaults/dangling.lua"
printf '%s\n' 'o.bind("SUPER + F4", "Platform linked slot", "platform-linked-slot")' >"$elsewhere/settings/slot.lua"
ln -s "$elsewhere/settings" "$linked/hypr/settings"
printf '%s\n' 'o.bind("SUPER + F3", "Platform upper", "platform-upper")' >"$linked/hypr/defaults/B.lua"
printf '%s\n' 'o.bind("SUPER + F2", "Platform lower", "platform-lower")' >"$linked/hypr/defaults/a.lua"
output=$(LC_ALL=en_US.UTF-8 PLATFORM_UNDER_TEST=$linked load_binds 2>"$tmpdir/stderr") || fail "bindings load with symlinked platform files" "$output"
grep -qxF $'SUPER + F5\tplatform-linked' <<<"$output" || fail "a symlinked platform file loads" "$output"
grep -qxF $'SUPER + F4\tplatform-linked-slot' <<<"$output" || fail "a symlinked slot directory loads" "$output"
! grep -q 'skipped' <<<"$output$(cat "$tmpdir/stderr")" || fail "a dangling symlink is skipped quietly" "$output"
[[ $(grep -e 'platform-upper' -e 'platform-lower' <<<"$output" | cut -f2 | paste -sd ' ') == "platform-upper platform-lower" ]] ||
  fail "platform files load in byte order whatever the locale" "$output"
pass "platform files load through symlinks, in byte order"
