-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- Port of A Dark Room script/fabricator.js.
--[[--
嗡鸣的制造机：探完残破战舰（Executioner）后出现，用外星合金制造流浪者装备。
带 blueprintRequired 的物品要先从战舰里带回对应蓝图（World:redeemBlueprints 登记到 character.blueprints）。
--]]
local Items = require("adarkroom.items")
local L = require("adarkroom.l10n")

local Fabricator = {}
Fabricator.__index = Fabricator

function Fabricator.new(engine)
    local self = setmetatable({ engine = engine, name = "fabricator" }, Fabricator)
    if not engine.state:get("features.location.fabricator") then
        engine.state:set("features.location.fabricator", true, true)
    end
    return self
end

function Fabricator:locationName() return L("A Whirring Fabricator") end

function Fabricator:onArrival()
    local sm = self.engine.state
    if not sm:get("game.fabricator.seen") then
        self.engine:notify(self, L("the familiar hum of wanderer machinery coming to life. finally, real tools."))
        sm:set("game.fabricator.seen", true)
    end
end

function Fabricator:canFabricate(item)
    return not item.blueprintRequired or self.engine.state:get('character.blueprints["' .. item.name .. '"]')
end

function Fabricator:fabricate(item)
    local engine, sm = self.engine, self.engine.state
    -- 原版这里写的是 Math.min(0, …)，numThings 恒 ≤ 0，所以 maximum 实际拦不住重复制造；
    -- 按钮本身会在达到上限时置灰（updateBuildButtons），这里照搬原版。
    local numThings = math.min(0, sm:get('stores["' .. item.name .. '"]', true))
    if item.maximum and item.maximum <= numThings then return false end
    local storeMod = {}
    for k, n in pairs(item.cost()) do
        local have = sm:get('stores["' .. k .. '"]', true)
        if have < n then
            engine:notify(self, L("not enough " .. k))
            return false
        end
        storeMod[k] = have - n
    end
    sm:setM("stores", storeMod)
    sm:add('stores["' .. item.name .. '"]', item.quantity or 1)
    engine:notify(self, item.buildMsg)
end

function Fabricator:view()
    local engine, sm = self.engine, self.engine.state
    local lines = {}
    local bps = sm:get("character.blueprints")
    if type(bps) == "table" then
        local names = {}
        for k, v in pairs(bps) do if v then names[#names + 1] = L(k) end end
        table.sort(names)
        if #names > 0 then
            lines[#lines + 1] = "【" .. L("blueprints") .. "】" .. table.concat(names, "，")
            lines[#lines + 1] = ""
        end
    end
    for _, l in ipairs(engine.modules.room:storesLines()) do lines[#lines + 1] = l end
    local buttons = { { label = L("fabricate:") } }
    for _, item in ipairs(Items.Fabricator) do
        if self:canFabricate(item) then
            local max = item.maximum and sm:get('stores["' .. item.name .. '"]', true) + 1 > item.maximum
            local name = L(item.label or item.name) .. ((item.quantity or 1) > 1 and (" (x" .. item.quantity .. ")") or "")
            buttons[#buttons + 1] = engine:button{ text = name, cost = item.cost(), enabled = not max,
                callback = function() return self:fabricate(item) end }
        end
    end
    return { title = self:locationName(), lines = lines, buttons = buttons }
end

return Fabricator
