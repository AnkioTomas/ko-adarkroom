-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- Port of A Dark Room script/room.js data: Craftables, TradeGoods, MiscItems.
--[[--
cost(sm) 返回 { store = n }。列表是有序数组（name = 原版 key），保证按钮顺序与原版一致。
--]]
local L = require("adarkroom.l10n")

local function fixed(t) return function() return t end end

local Items = {}

Items.Craftables = {
    { name = "trap", maximum = 10, type = "building",
      availableMsg = L("builder says she can make traps to catch any creatures might still be alive out there"),
      buildMsg = L("more traps to catch more creatures"), maxMsg = L("more traps won't help now"),
      cost = function(sm) return { wood = 10 + sm:get('game.buildings["trap"]', true) * 10 } end },
    { name = "cart", maximum = 1, type = "building",
      availableMsg = L("builder says she can make a cart for carrying wood"),
      buildMsg = L("the rickety cart will carry more wood from the forest"), cost = fixed{ wood = 30 } },
    { name = "hut", maximum = 20, type = "building",
      availableMsg = L("builder says there are more wanderers. says they'll work, too."),
      buildMsg = L("builder puts up a hut, out in the forest. says word will get around."),
      maxMsg = L("no more room for huts."),
      cost = function(sm) return { wood = 100 + sm:get('game.buildings["hut"]', true) * 50 } end },
    { name = "lodge", maximum = 1, type = "building",
      availableMsg = L("villagers could help hunt, given the means"),
      buildMsg = L("the hunting lodge stands in the forest, a ways out of town"), cost = fixed{ wood = 200, fur = 10, meat = 5 } },
    { name = "trading post", maximum = 1, type = "building",
      availableMsg = L("a trading post would make commerce easier"),
      buildMsg = L("now the nomads have a place to set up shop, they might stick around a while"), cost = fixed{ wood = 400, fur = 100 } },
    { name = "tannery", maximum = 1, type = "building",
      availableMsg = L("builder says leather could be useful. says the villagers could make it."),
      buildMsg = L("tannery goes up quick, on the edge of the village"), cost = fixed{ wood = 500, fur = 50 } },
    { name = "smokehouse", maximum = 1, type = "building",
      availableMsg = L("should cure the meat, or it'll spoil. builder says she can fix something up."),
      buildMsg = L("builder finishes the smokehouse. she looks hungry."), cost = fixed{ wood = 600, meat = 50 } },
    { name = "workshop", maximum = 1, type = "building",
      availableMsg = L("builder says she could make finer things, if she had the tools"),
      buildMsg = L("workshop's finally ready. builder's excited to get to it"), cost = fixed{ wood = 800, leather = 100, scales = 10 } },
    { name = "steelworks", maximum = 1, type = "building",
      availableMsg = L("builder says the villagers could make steel, given the tools"),
      buildMsg = L("a haze falls over the village as the steelworks fires up"), cost = fixed{ wood = 1500, iron = 100, coal = 100 } },
    { name = "armoury", maximum = 1, type = "building",
      availableMsg = L("builder says it'd be useful to have a steady source of bullets"),
      buildMsg = L("armoury's done, welcoming back the weapons of the past."), cost = fixed{ wood = 3000, steel = 100, sulphur = 50 } },
    { name = "torch", type = "tool", buildMsg = L("a torch to keep the dark away"), cost = fixed{ wood = 1, cloth = 1 } },
    { name = "waterskin", type = "upgrade", maximum = 1, buildMsg = L("this waterskin'll hold a bit of water, at least"), cost = fixed{ leather = 50 } },
    { name = "cask", type = "upgrade", maximum = 1, buildMsg = L("the cask holds enough water for longer expeditions"), cost = fixed{ leather = 100, iron = 20 } },
    { name = "water tank", type = "upgrade", maximum = 1, buildMsg = L("never go thirsty again"), cost = fixed{ iron = 100, steel = 50 } },
    { name = "bone spear", type = "weapon", buildMsg = L("this spear's not elegant, but it's pretty good at stabbing"), cost = fixed{ wood = 100, teeth = 5 } },
    { name = "rucksack", type = "upgrade", maximum = 1, buildMsg = L("carrying more means longer expeditions to the wilds"), cost = fixed{ leather = 200 } },
    { name = "wagon", type = "upgrade", maximum = 1, buildMsg = L("the wagon can carry a lot of supplies"), cost = fixed{ wood = 500, iron = 100 } },
    { name = "convoy", type = "upgrade", maximum = 1, buildMsg = L("the convoy can haul mostly everything"), cost = fixed{ wood = 1000, iron = 200, steel = 100 } },
    { name = "l armour", type = "upgrade", maximum = 1, buildMsg = L("leather's not strong. better than rags, though."), cost = fixed{ leather = 200, scales = 20 } },
    { name = "i armour", type = "upgrade", maximum = 1, buildMsg = L("iron's stronger than leather"), cost = fixed{ leather = 200, iron = 100 } },
    { name = "s armour", type = "upgrade", maximum = 1, buildMsg = L("steel's stronger than iron"), cost = fixed{ leather = 200, steel = 100 } },
    { name = "iron sword", type = "weapon", buildMsg = L("sword is sharp. good protection out in the wilds."), cost = fixed{ wood = 200, leather = 50, iron = 20 } },
    { name = "steel sword", type = "weapon", buildMsg = L("the steel is strong, and the blade true."), cost = fixed{ wood = 500, leather = 100, steel = 20 } },
    { name = "rifle", type = "weapon", buildMsg = L("black powder and bullets, like the old days."), cost = fixed{ wood = 200, steel = 50, sulphur = 50 } },
}

Items.TradeGoods = {
    { name = "scales", type = "good", cost = fixed{ fur = 150 } },
    { name = "teeth", type = "good", cost = fixed{ fur = 300 } },
    { name = "iron", type = "good", cost = fixed{ fur = 150, scales = 50 } },
    { name = "coal", type = "good", cost = fixed{ fur = 200, teeth = 50 } },
    { name = "steel", type = "good", cost = fixed{ fur = 300, scales = 50, teeth = 50 } },
    { name = "medicine", type = "good", cost = fixed{ scales = 50, teeth = 30 } },
    { name = "bullets", type = "good", cost = fixed{ scales = 10 } },
    { name = "energy cell", type = "good", cost = fixed{ scales = 10, teeth = 10 } },
    { name = "bolas", type = "weapon", cost = fixed{ teeth = 10 } },
    { name = "grenade", type = "weapon", cost = fixed{ scales = 100, teeth = 50 } },
    { name = "bayonet", type = "weapon", cost = fixed{ scales = 500, teeth = 250 } },
    { name = "alien alloy", type = "good", cost = fixed{ fur = 1500, scales = 750, teeth = 300 } },
    { name = "compass", type = "special", maximum = 1, cost = fixed{ fur = 400, scales = 20, teeth = 10 } },
}

Items.MiscItems = { { name = "laser rifle", type = "weapon" } }

Items.byName = {}
for _, list in ipairs({ Items.MiscItems, Items.TradeGoods, Items.Craftables }) do
    for _, it in ipairs(list) do Items.byName[it.name] = it end
end

--- 是否在原版 Room.Craftables 里
function Items.isCraftable(name)
    for _, it in ipairs(Items.Craftables) do if it.name == name then return true end end
    return false
end

--- 原版 $SM.num：建筑数在 game.buildings，其余在 stores。
function Items.num(sm, name, item)
    if item.type == "building" then return sm:get('game.buildings["' .. name .. '"]', true) end
    return sm:get('stores["' .. name .. '"]', true)
end

--- 花费表转成稳定顺序的显示串："木头 10，皮毛 5"
function Items.costText(cost)
    local keys = {}
    for k in pairs(cost) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = L(k) .. " " .. cost[k] end
    return table.concat(parts, "，")
end

return Items
