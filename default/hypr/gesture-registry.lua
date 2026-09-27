-- What Hyprland 0.56 does with an hl.gesture call, told from the call alone.
-- hl.gesture returns nothing and raises nothing when it refuses a gesture (it
-- reports a config error), and Lua can't list the gestures Hyprland holds, so
-- the gesture registry (helpers.lua) predicts each verdict from the checks
-- hlGesture (LuaBindingsConfigRules.cpp) and CTrackpadGestures::addGesture
-- and removeGesture make. A Hyprland that changes those needs this file
-- checked again.

local M = {}

-- CTrackpadGestures::dirForString, by the full name the registry records.
local directions = {
  swipe = "swipe",
  left = "left",
  l = "left",
  right = "right",
  r = "right",
  up = "up",
  u = "up",
  top = "up",
  t = "up",
  down = "down",
  d = "down",
  bottom = "down",
  b = "down",
  horizontal = "horizontal",
  horiz = "horizontal",
  vertical = "vertical",
  vert = "vertical",
  pinch = "pinch",
  pinchin = "pinchin",
  zoomin = "pinchin",
  pinchout = "pinchout",
  zoomout = "pinchout",
}

-- The axis addGesture compares a new gesture's direction by.
local axes = {
  left = "horizontal",
  right = "horizontal",
  horizontal = "horizontal",
  up = "vertical",
  down = "vertical",
  vertical = "vertical",
  swipe = "swipe",
  pinch = "pinch",
  pinchin = "pinch",
  pinchout = "pinch",
}

local actions = {
  workspace = true,
  resize = true,
  move = true,
  special = true,
  close = true,
  float = true,
  fullscreen = true,
  cursor_zoom = true,
  cursorZoom = true,
  scroll_move = true,
  unset = true,
}

-- KeybindManager::stringToModMask: a modifier counts wherever its name appears,
-- so "NONE" or "" holds none.
local modifiers = {
  { "SHIFT", 1 },
  { "CAPS", 2 },
  { "CTRL", 4 },
  { "CONTROL", 4 },
  { "ALT", 8 },
  { "MOD1", 8 },
  { "MOD2", 16 },
  { "MOD3", 32 },
  { "SUPER", 64 },
  { "WIN", 64 },
  { "LOGO", 64 },
  { "MOD4", 64 },
  { "META", 64 },
  { "MOD5", 128 },
}

-- lua_isstring: a string, or a number Lua turns into one.
local function stringy(value)
  return type(value) == "string" or type(value) == "number"
end

local function mod_mask(mods)
  local mask = 0
  local text = tostring(mods or ""):upper()
  for _, modifier in ipairs(modifiers) do
    if text:find(modifier[1], 1, true) then
      mask = mask | modifier[2]
    end
  end
  return mask
end

-- Hyprland keeps a float setting as a C float.
local function as_float(number)
  return (string.unpack("f", string.pack("f", number)))
end

-- CLuaConfigFloat: a boolean reads as 0 or 1, and a number or a string that
-- reads as one as that number. The bounds, C floats themselves, are checked
-- against it before it's stored as a C float.
local function float_field(value, min, max)
  local number = type(value) == "boolean" and (value and 1 or 0) or tonumber(value)
  if not number or number < as_float(min) or number > as_float(max) then
    return nil
  end
  return as_float(number)
end

-- CLuaConfigBool: a boolean, or a number (or a string that reads as one) that
-- is 0 or 1.
local function bool_field(value)
  if type(value) == "boolean" then
    return value
  end
  local number = tonumber(value)
  if number == 0 or number == 1 then
    return number == 1
  end
  return nil
end

-- Returns "add" and the gesture as the registry records it, "remove" and the
-- index of the recorded gesture an unset takes away, or nil when Hyprland
-- refuses the call. `registered` is what the registry recorded so far.
function M.verdict(registered, gesture)
  if type(gesture) ~= "table" then
    return nil
  end

  local fingers = gesture.fingers
  if math.type(fingers) ~= "integer" or fingers < 2 or fingers > 9 then
    return nil
  end

  local direction = stringy(gesture.direction) and directions[tostring(gesture.direction):lower()]
  if not direction then
    return nil
  end

  -- A callback table needs at least one callback, and each one it has must be
  -- a function. Anything but a function or a table names an action.
  local action = gesture.action
  local unset = false
  if type(action) == "table" then
    local callbacks = 0
    for _, name in ipairs({ "start", "update", "finish" }) do
      local callback = action[name]
      if callback ~= nil then
        if type(callback) ~= "function" then
          return nil
        end
        callbacks = callbacks + 1
      end
    end
    if callbacks == 0 then
      return nil
    end
  elseif type(action) ~= "function" then
    if not (stringy(action) and actions[tostring(action)]) then
      return nil
    end
    unset = tostring(action) == "unset"
  end

  for _, field in ipairs({ "zoom_level", "workspace_name", "mode", "mods" }) do
    if gesture[field] ~= nil and not stringy(gesture[field]) then
      return nil
    end
  end

  local scale = as_float(1)
  if gesture.scale ~= nil then
    scale = float_field(gesture.scale, 0.1, 10)
    if not scale then
      return nil
    end
  end

  local disable_inhibit = false
  if gesture.disable_inhibit ~= nil then
    disable_inhibit = bool_field(gesture.disable_inhibit)
    if disable_inhibit == nil then
      return nil
    end
  end

  local mods = mod_mask(gesture.mods)

  -- removeGesture takes away the first gesture that matches exactly, and
  -- refuses when none does.
  if unset then
    for index, recorded in ipairs(registered) do
      if recorded.fingers == fingers and recorded.direction == direction and recorded.mods == mods and
        recorded.scale == scale and recorded.disable_inhibit == disable_inhibit then
        return "remove", index
      end
    end
    return nil
  end

  -- addGesture refuses a gesture on the same fingers and modifiers once an
  -- earlier one covers its direction or its axis, or it is sideways or up and
  -- down and an earlier one takes any swipe.
  local axis = axes[direction]
  for _, recorded in ipairs(registered) do
    if recorded.fingers == fingers and recorded.mods == mods and
      (recorded.direction == axis or recorded.direction == direction or
        ((axis == "horizontal" or axis == "vertical") and recorded.direction == "swipe")) then
      return nil
    end
  end

  return "add", {
    fingers = fingers,
    direction = direction,
    modified = mods ~= 0,
    mods = mods,
    scale = scale,
    disable_inhibit = disable_inhibit,
  }
end

return M
