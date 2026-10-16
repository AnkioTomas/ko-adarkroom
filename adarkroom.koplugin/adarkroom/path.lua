-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- Port of A Dark Room script/path.js.
--[[--
漫漫尘途：出发前整理背包（outfit），出发后切到世界地图。
背包内容存在状态树 outfit（原版 Path.outfit 与 $SM 'outfit' 同一份）。
--]]
local Items = require("adarkroom.items")
local L = require("adarkroom.l10n")

local Path = {}
Path.__index = Path

Path.DEFAULT_BAG_SPACE = 10
-- 不在表里的物品重量为 1
Path.Weight = {
    ["bone spear"] = 2, ["iron sword"] = 3, ["steel sword"] = 5, ["rifle"] = 5, ["bullets"] = 0.1,
    ["energy cell"] = 0.2, ["laser rifle"] = 5, ["plasma rifle"] = 5, ["bolas"] = 0.5,
}

-- 原版 updateOutfitting 里追加的非 Craftables 可携带物
Path.EXTRA = {
    { name = "cured meat", type = "tool" }, { name = "bullets", type = "tool" }, { name = "grenade", type = "weapon" },
    { name = "bolas", type = "weapon" }, { name = "laser rifle", type = "weapon" }, { name = "energy cell", type = "tool" },
    { name = "bayonet", type = "weapon" }, { name = "charm", type = "tool" }, { name = "alien alloy", type = "tool" },
    { name = "medicine", type = "tool" },
}

function Path.new(engine)
    local self = setmetatable({ engine = engine, name = "path" }, Path)
    local world = engine:module("world")
    engine.state:set("features.location.path", true, true)
    self.carryable = {}
    for _, it in ipairs(Path.EXTRA) do self.carryable[#self.carryable + 1] = it end
    for _, it in ipairs(Items.Craftables) do
        if it.type == "tool" or it.type == "weapon" then self.carryable[#self.carryable + 1] = it end
    end
    self.world = world
    return self
end

function Path:locationName() return L("A Dusty Path") end

--- 原版 Path.openPath：第一次拿到罗盘时调用。
function Path:announce()
    self.engine:notify(self.engine.modules.room, L("the compass points " .. self.world.dir))
end

function Path:outfit()
    local sm = self.engine.state
    local o = sm:get("outfit")
    if type(o) ~= "table" then
        o = {}
        sm:set("outfit", o, true)
    end
    return o
end

function Path.getWeight(thing) return Path.Weight[thing] or 1 end

function Path:getCapacity()
    local sm = self.engine.state
    if sm:get('stores["cargo drone"]', true) > 0 then return Path.DEFAULT_BAG_SPACE + 100
    elseif sm:get("stores.convoy", true) > 0 then return Path.DEFAULT_BAG_SPACE + 60
    elseif sm:get("stores.wagon", true) > 0 then return Path.DEFAULT_BAG_SPACE + 30
    elseif sm:get("stores.rucksack", true) > 0 then return Path.DEFAULT_BAG_SPACE + 10 end
    return Path.DEFAULT_BAG_SPACE
end

function Path:getFreeSpace()
    local num = 0
    for k, n in pairs(self:outfit()) do
        if type(n) ~= "number" or n ~= n then n = 0 end
        num = num + n * Path.getWeight(k)
    end
    return self:getCapacity() - num
end

function Path:armour()
    local sm = self.engine.state
    if sm:get('stores["kinetic armour"]', true) > 0 then return L("kinetic")
    elseif sm:get('stores["s armour"]', true) > 0 then return L("steel")
    elseif sm:get('stores["i armour"]', true) > 0 then return L("iron")
    elseif sm:get('stores["l armour"]', true) > 0 then return L("leather") end
    return L("none")
end

function Path:increaseSupply(supply, amt)
    local sm = self.engine.state
    local outfit = self:outfit()
    local cur = outfit[supply] or 0
    local have = sm:get('stores["' .. supply .. '"]', true)
    local w = Path.getWeight(supply)
    if self:getFreeSpace() >= w and cur < have then
        local byWeight = math.floor(self:getFreeSpace() / w)
        outfit[supply] = cur + math.min(amt, byWeight, have - cur)
        sm:set("outfit", outfit)
    end
end

function Path:decreaseSupply(supply, amt)
    local outfit = self:outfit()
    local cur = outfit[supply] or 0
    if cur > 0 then
        outfit[supply] = math.max(0, cur - amt)
        self.engine.state:set("outfit", outfit)
    end
end

--- 背包数量不能超过库存（原版 updateOutfitting 的修正）
function Path:clampOutfit()
    local sm = self.engine.state
    local outfit = self:outfit()
    for k, n in pairs(outfit) do
        local have = sm:get('stores["' .. k .. '"]')
        if type(have) == "number" and have < n then outfit[k] = have end
    end
end

function Path:onArrival() self:clampOutfit() end

function Path:embark()
    local sm = self.engine.state
    for k, n in pairs(self:outfit()) do sm:add('stores["' .. k .. '"]', -n) end
    self.engine:travelTo(self.world) -- World:onArrival 建立临时世界状态
end

function Path:view()
    local engine, sm = self.engine, self.engine.state
    self:clampOutfit()
    local outfit = self:outfit()
    local lines = {
        L("armour") .. "：" .. self:armour(),
        L("water") .. "：" .. self.world:getMaxWater(),
        L("free {0}/{1}", math.floor(self:getFreeSpace()), self:getCapacity()),
    }
    local perks = {}
    for k, v in pairs(sm:get("character.perks") or {}) do
        if v then perks[#perks + 1] = (engine.Perks[k] and engine.Perks[k].name or k) end
    end
    if #perks > 0 then
        table.sort(perks)
        lines[#lines + 1] = "【" .. "技能" .. "】" .. table.concat(perks, "，")
    end
    local buttons = {}
    local space = self:getFreeSpace()
    for _, it in ipairs(self.carryable) do
        local have = sm:get('stores["' .. it.name .. '"]', true)
        if have > 0 then
            local n = outfit[it.name] or 0
            local canAdd = n < have and space >= Path.getWeight(it.name)
            buttons[#buttons + 1] = {
                { text = L(it.name) .. " " .. n .. "/" .. math.floor(have), enabled = false, callback = function() end },
                { text = "−10", enabled = n > 0, callback = function() self:decreaseSupply(it.name, 10) end },
                { text = "−1", enabled = n > 0, callback = function() self:decreaseSupply(it.name, 1) end },
                { text = "+1", enabled = canAdd, callback = function() self:increaseSupply(it.name, 1) end },
                { text = "+10", enabled = canAdd, callback = function() self:increaseSupply(it.name, 10) end },
            }
        end
    end
    buttons[#buttons + 1] = engine:button{ id = "embark", text = L("embark"), cooldown = 0,
        enabled = (outfit["cured meat"] or 0) > 0, callback = function() self:embark() end }
    return { title = self:locationName(), lines = lines, buttons = buttons }
end

return Path
