local PLANNER = "turret-ammo-planner"

local GUI_FRAME = "tap_frame"
local GUI_AMMO = "tap_ammo"
local GUI_COUNT = "tap_count"
local GUI_QUALITY = "tap_quality"
local GUI_MODE = "tap_mode"
local GUI_GIVE = "tap_give_planner"
local GUI_CLOSE = "tap_close"

local DEFAULT_AMMO = "firearm-magazine"
local DEFAULT_COUNT = 10
local DEFAULT_QUALITY = "normal"
local DEFAULT_MODE = "set"

local MODE_SET = "set"
local MODE_TOP_UP = "top-up"
local MODE_CLEAR = "clear"

local QUALITY_NAMES = {
  "normal",
  "uncommon",
  "rare",
  "epic",
  "legendary"
}

local function ensure_storage()
  storage.players = storage.players or {}
end

local function get_player(event)
  if not event or not event.player_index then return nil end
  return game.get_player(event.player_index)
end

local function get_config(player)
  ensure_storage()

  storage.players[player.index] = storage.players[player.index] or {
    ammo = DEFAULT_AMMO,
    count = DEFAULT_COUNT,
    quality = DEFAULT_QUALITY,
    mode = DEFAULT_MODE
  }

  local config = storage.players[player.index]

  config.ammo = config.ammo or DEFAULT_AMMO
  config.count = config.count or DEFAULT_COUNT
  config.quality = config.quality or DEFAULT_QUALITY
  config.mode = config.mode or DEFAULT_MODE

  return config
end

local function parse_count(value)
  local count = tonumber(value)
  if not count then return DEFAULT_COUNT end

  count = math.floor(count)

  if count < 0 then count = 0 end
  if count > 10000 then count = 10000 end

  return count
end

local function is_ammo_item(name)
  local proto = name and prototypes.item[name]
  return proto and proto.type == "ammo"
end

local function is_supported_turret(entity)
  return entity
    and entity.valid
    and (
      entity.type == "ammo-turret"
      or entity.type == "artillery-turret"
    )
end

local function get_turret_ammo_inventory(turret)
  local ok, inv = pcall(function()
    return turret.get_inventory(defines.inventory.turret_ammo)
  end)

  if ok and inv and inv.valid then
    return inv
  end

  return nil
end

local function count_ammo_in_turret(inv, ammo, quality)
  local total = 0

  for i = 1, #inv do
    local stack = inv[i]
    if stack and stack.valid_for_read and stack.name == ammo then
      local stack_quality = stack.quality and stack.quality.name or "normal"
      if stack_quality == quality then
        total = total + stack.count
      end
    end
  end

  return total
end

local function make_insert_plan(ammo, quality, count)
  return {
    {
      id = {
        name = ammo,
        quality = quality
      },
      items = {
        in_inventory = {
          {
            inventory = defines.inventory.turret_ammo,
            stack = 0,
            count = count
          }
        }
      }
    }
  }
end

local function make_removal_plan_from_inventory(inv)
  local removal_plan = {}

  for i = 1, #inv do
    local stack = inv[i]

    if stack and stack.valid_for_read and stack.count > 0 then
      local quality = stack.quality and stack.quality.name or "normal"

      removal_plan[#removal_plan + 1] = {
        id = {
          name = stack.name,
          quality = quality
        },
        items = {
          in_inventory = {
            {
              inventory = defines.inventory.turret_ammo,
              stack = i - 1,
              count = stack.count
            }
          }
        }
      }
    end
  end

  return removal_plan
end

local function destroy_existing_proxy(turret)
  if turret.item_request_proxy and turret.item_request_proxy.valid then
    turret.item_request_proxy.destroy()
  end
end

local function create_proxy(turret, player, insert_plan, removal_plan)
  destroy_existing_proxy(turret)

  local params = {
    name = "item-request-proxy",
    position = turret.position,
    force = turret.force,
    target = turret,
    player = player,
    modules = insert_plan
  }

  if removal_plan and #removal_plan > 0 then
    params.removal_plan = removal_plan
  end

  return turret.surface.create_entity(params)
end

local function apply_request_to_turret(turret, player, config, force_clear)
  local inv = get_turret_ammo_inventory(turret)
  if not inv then
    return false, "no turret ammo inventory"
  end

  local mode = force_clear and MODE_CLEAR or config.mode

  local removal_plan = nil
  local insert_plan = nil

  if mode == MODE_CLEAR then
    removal_plan = make_removal_plan_from_inventory(inv)

    if #removal_plan == 0 then
      destroy_existing_proxy(turret)
      return true, "already empty"
    end

    create_proxy(turret, player, {}, removal_plan)
    return true, "clear requested"
  end

  if not is_ammo_item(config.ammo) then
    return false, "selected item is not ammo"
  end

  if config.count <= 0 then
    return false, "count must be greater than zero"
  end

  if mode == MODE_SET then
    removal_plan = make_removal_plan_from_inventory(inv)
    insert_plan = make_insert_plan(config.ammo, config.quality, config.count)

    create_proxy(turret, player, insert_plan, removal_plan)
    return true, "set request created"
  end

  if mode == MODE_TOP_UP then
    local current = count_ammo_in_turret(inv, config.ammo, config.quality)
    local needed = config.count - current

    if needed <= 0 then
      return true, "already has enough"
    end

    insert_plan = make_insert_plan(config.ammo, config.quality, needed)
    create_proxy(turret, player, insert_plan, nil)
    return true, "top-up request created"
  end

  return false, "unknown mode"
end

local function give_planner(player)
  if not player or not player.valid then return end

  if player.cursor_stack and player.cursor_stack.valid and not player.cursor_stack.valid_for_read then
    player.cursor_stack.set_stack{
      name = PLANNER,
      count = 1
    }
    return
  end

  local inserted = player.insert{
    name = PLANNER,
    count = 1
  }

  if inserted > 0 then
    player.print({"turret-ammo-planner.planner-added"})
  else
    player.print({"turret-ammo-planner.no-inventory-space"})
  end
end

local function destroy_gui(player)
  local frame = player.gui.screen[GUI_FRAME]
  if frame then frame.destroy() end
end

local function quality_index(quality)
  for i, q in ipairs(QUALITY_NAMES) do
    if q == quality then return i end
  end

  return 1
end

local function build_gui(player)
  destroy_gui(player)

  local config = get_config(player)

  local frame = player.gui.screen.add{
    type = "frame",
    name = GUI_FRAME,
    direction = "vertical",
    caption = {"turret-ammo-planner.gui-title"}
  }

  frame.auto_center = true

  local body = frame.add{
    type = "flow",
    direction = "vertical"
  }

  body.style.padding = 8
  body.style.vertical_spacing = 8

  body.add{
    type = "label",
    caption = {"turret-ammo-planner.ammo-label"}
  }

  body.add{
    type = "choose-elem-button",
    name = GUI_AMMO,
    elem_type = "item",
    item = config.ammo
  }

  body.add{
    type = "label",
    caption = {"turret-ammo-planner.count-label"}
  }

  body.add{
    type = "textfield",
    name = GUI_COUNT,
    text = tostring(config.count),
    numeric = true,
    allow_decimal = false,
    allow_negative = false
  }

  body.add{
    type = "label",
    caption = {"turret-ammo-planner.quality-label"}
  }

  local quality_dropdown = body.add{
    type = "drop-down",
    name = GUI_QUALITY,
    items = {
      "normal",
      "uncommon",
      "rare",
      "epic",
      "legendary"
    }
  }

  quality_dropdown.selected_index = quality_index(config.quality)

  body.add{
    type = "label",
    caption = {"turret-ammo-planner.mode-label"}
  }

  local mode_dropdown = body.add{
    type = "drop-down",
    name = GUI_MODE,
    items = {
      {"turret-ammo-planner.mode-set"},
      {"turret-ammo-planner.mode-top-up"},
      {"turret-ammo-planner.mode-clear"}
    }
  }

  if config.mode == MODE_SET then
    mode_dropdown.selected_index = 1
  elseif config.mode == MODE_TOP_UP then
    mode_dropdown.selected_index = 2
  elseif config.mode == MODE_CLEAR then
    mode_dropdown.selected_index = 3
  else
    mode_dropdown.selected_index = 1
  end

  local buttons = body.add{
    type = "flow",
    direction = "horizontal"
  }

  buttons.style.horizontal_spacing = 8

  buttons.add{
    type = "button",
    name = GUI_GIVE,
    caption = {"turret-ammo-planner.give-planner"}
  }

  buttons.add{
    type = "button",
    name = GUI_CLOSE,
    caption = {"turret-ammo-planner.close"}
  }

  body.add{
    type = "label",
    caption = {"turret-ammo-planner.help"}
  }
end

local function toggle_gui(player)
  if not player or not player.valid then return end

  if player.gui.screen[GUI_FRAME] then
    destroy_gui(player)
  else
    build_gui(player)
  end
end

local function save_gui_value(event)
  local player = get_player(event)
  if not player then return end

  local element = event.element
  if not element or not element.valid then return end

  local config = get_config(player)

  if element.name == GUI_AMMO then
    if element.elem_value then
      config.ammo = element.elem_value
    end
    return
  end

  if element.name == GUI_COUNT then
    config.count = parse_count(element.text)
    return
  end

  if element.name == GUI_QUALITY then
    config.quality = QUALITY_NAMES[element.selected_index] or DEFAULT_QUALITY
    return
  end

  if element.name == GUI_MODE then
    if element.selected_index == 1 then
      config.mode = MODE_SET
    elseif element.selected_index == 2 then
      config.mode = MODE_TOP_UP
    elseif element.selected_index == 3 then
      config.mode = MODE_CLEAR
    end
    return
  end
end

local function handle_gui_click(event)
  local player = get_player(event)
  if not player then return end

  local element = event.element
  if not element or not element.valid then return end

  if element.name == GUI_GIVE then
    give_planner(player)
    return
  end

  if element.name == GUI_CLOSE then
    destroy_gui(player)
    return
  end
end

local function handle_selection(event, force_clear)
  if event.item ~= PLANNER then return end

  local player = get_player(event)
  if not player then return end

  local config = get_config(player)

  local changed = 0
  local skipped = 0
  local last_reason = nil

  for _, entity in pairs(event.entities or {}) do
    if is_supported_turret(entity) then
      local ok, reason = apply_request_to_turret(entity, player, config, force_clear)

      if ok then
        changed = changed + 1
      else
        skipped = skipped + 1
        last_reason = reason
      end
    end
  end

  local msg

  if force_clear or config.mode == MODE_CLEAR then
    msg = "Created clear requests for " .. changed .. " turret(s)"
  elseif config.mode == MODE_TOP_UP then
    msg = "Created top-up requests for " .. changed .. " turret(s)"
  else
    msg = "Created set requests for " .. changed .. " turret(s)"
  end

  if skipped > 0 then
    msg = msg .. "; skipped " .. skipped
    if last_reason then
      msg = msg .. " (" .. last_reason .. ")"
    end
  end

  player.create_local_flying_text{
    text = msg,
    position = player.position
  }
end

script.on_init(function()
  ensure_storage()
end)

script.on_configuration_changed(function()
  ensure_storage()
end)

script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name == "turret-ammo-planner-toggle-gui" then
    toggle_gui(get_player(event))
  end
end)

script.on_event("turret-ammo-planner-toggle-gui", function(event)
  toggle_gui(get_player(event))
end)

script.on_event(defines.events.on_gui_click, handle_gui_click)
script.on_event(defines.events.on_gui_text_changed, save_gui_value)
script.on_event(defines.events.on_gui_selection_state_changed, save_gui_value)
script.on_event(defines.events.on_gui_elem_changed, save_gui_value)

script.on_event(defines.events.on_player_selected_area, function(event)
  handle_selection(event, false)
end)

script.on_event(defines.events.on_player_alt_selected_area, function(event)
  handle_selection(event, true)
end)