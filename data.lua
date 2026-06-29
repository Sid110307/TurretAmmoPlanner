local planner_name = "turret-ammo-planner"

data:extend({
  {
    type = "selection-tool",
    name = planner_name,

    icon = "__base__/graphics/icons/upgrade-planner.png",
    icon_size = 64,

    subgroup = "tool",
    order = "c[automated-construction]-z[turret-ammo-planner]",
    stack_size = 1,

    flags = { "only-in-cursor", "spawnable" },

    select = {
      border_color = { r = 0.2, g = 1.0, b = 0.2, a = 1.0 },
      cursor_box_type = "entity",
      mode = { "buildable-type", "same-force" },
      entity_type_filters = { "ammo-turret", "artillery-turret" },
      entity_filter_mode = "whitelist"
    },

    alt_select = {
      border_color = { r = 1.0, g = 0.2, b = 0.2, a = 1.0 },
      cursor_box_type = "entity",
      mode = { "buildable-type", "same-force" },
      entity_type_filters = { "ammo-turret", "artillery-turret" },
      entity_filter_mode = "whitelist"
    }
  },

  {
    type = "shortcut",
    name = "turret-ammo-planner-toggle-gui",
    order = "a[alt-mode]-z[turret-ammo-planner]",
    action = "lua",
    toggleable = false,
    associated_control_input = "turret-ammo-planner-toggle-gui",
    icon = "__base__/graphics/icons/upgrade-planner.png",
    icon_size = 64,
    small_icon = "__base__/graphics/icons/upgrade-planner.png",
    small_icon_size = 64
  },

  {
    type = "custom-input",
    name = "turret-ammo-planner-toggle-gui",
    key_sequence = "CONTROL + SHIFT + T",
    consuming = "none",
    action = "lua"
  }
})