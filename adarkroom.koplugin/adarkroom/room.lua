-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- Port of A Dark Room script/room.js (logic; data lives in adarkroom/items.lua).
local Items = require("adarkroom.items")
local L = require("adarkroom.l10n")

local Room = {}
Room.__index = Room

Room.FIRE_COOL_DELAY = 5 * 60   -- 秒
Room.ROOM_WARM_DELAY = 30
Room.BUILDER_STATE_DELAY = 30
Room.STOKE_COOLDOWN = 10
Room.NEED_WOOD_DELAY = 15
Room.TEMP = { "freezing", "cold", "mild", "warm", "hot" }      -- value 0..4
Room.FIRE = { "dead", "smoldering", "flickering", "burning", "roaring" }

--[[ Builder states: 0 approaching, 1 collapsed, 2 shivering, 3 sleeping, 4 helping ]]

function Room.new(engine)
    local self = setmetatable({ engine = engine, name = "room", unlocked = {} }, Room)
    local sm = engine.state
    if sm:get("features.location.room") == nil then
        sm:set("features.location.room", true, true)
        sm:set("game.builder.level", -1, true)
    end
    if sm:get("game.temperature.value") == nil then sm:set("game.temperature", { value = 0 }, true) end
    if sm:get("game.fire.value") == nil then sm:set("game.fire", { value = 0 }, true) end
    if sm:get("game.builder.level") == nil then sm:set("game.builder.level", -1, true) end

    self.fireTimer = engine:setTimeout(function() self:coolFire() end, Room.FIRE_COOL_DELAY)
    self.tempTimer = engine:setTimeout(function() self:adjustTemp() end, Room.ROOM_WARM_DELAY)
    local lb = self:builder()
    if lb >= 0 and lb < 3 then
        engine:setTimeout(function() self:updateBuilderState() end, Room.BUILDER_STATE_DELAY)
    end
    if lb == 1 and sm:get("stores.wood", true) < 0 then
        engine:setTimeout(function() self:unlockForest() end, Room.NEED_WOOD_DELAY)
    end
    engine.dispatch:subscribe("stateUpdate", function(e) self:handleStateUpdates(e) end)
    self:updateBuildButtons(true)
    return self
end

function Room:fire() return self.engine.state:get("game.fire.value") or 0 end
function Room:temp() return self.engine.state:get("game.temperature.value") or 0 end
function Room:builder() return self.engine.state:get("game.builder.level") or -1 end
function Room:locationName() return self:fire() < 2 and L("A Dark Room") or L("A Firelit Room") end

function Room:notify(text, noQueue) self.engine:notify(self, text, noQueue) end

function Room:onArrival()
    if self.changed or not self.arrived then
        self:notify(L("the room is {0}", L(Room.TEMP[self:temp() + 1])))
        self:notify(L("the fire is {0}", L(Room.FIRE[self:fire() + 1])))
        self.changed, self.arrived = false, true
    end
    local sm = self.engine.state
    if self:builder() == 3 then
        sm:add("game.builder.level", 1)
        sm:setIncome("builder", { delay = 10, stores = { wood = 2 } })
        self:notify(L("the stranger is standing by the fire. she says she can help. says she builds things."))
    end
end

-- FIRE -----------------------------------------------------------------------
function Room:lightFire()
    local sm = self.engine.state
    local wood = sm:get("stores.wood")
    if type(wood) == "number" and wood < 5 then
        self:notify(L("not enough wood to get the fire going"))
        return false
    elseif type(wood) == "number" then
        sm:set("stores.wood", wood - 5)
    end
    sm:set("game.fire", { value = 3 })
    self:onFireChange()
end

function Room:stokeFire()
    local sm = self.engine.state
    local wood = sm:get("stores.wood")
    if wood == 0 then
        self:notify(L("the wood has run out"))
        return false
    end
    if type(wood) == "number" then sm:set("stores.wood", wood - 1) end
    if self:fire() < 4 then sm:set("game.fire", { value = self:fire() + 1 }) end
    self:onFireChange()
end

function Room:onFireChange()
    local sm = self.engine.state
    if self.engine.activeModule ~= self then self.changed = true end
    self:notify(L("the fire is {0}", L(Room.FIRE[self:fire() + 1])), true)
    if self:fire() > 1 and self:builder() < 0 then
        sm:set("game.builder.level", 0)
        self:notify(L("the light from the fire spills from the windows, out into the dark"))
        self.engine:setTimeout(function() self:updateBuilderState() end, Room.BUILDER_STATE_DELAY)
    end
    self.engine:clearTimeout(self.fireTimer)
    self.fireTimer = self.engine:setTimeout(function() self:coolFire() end, Room.FIRE_COOL_DELAY)
    self.engine:requestRender()
end

function Room:coolFire()
    local sm = self.engine.state
    local wood = sm:get("stores.wood")
    if self:fire() <= 2 and self:builder() > 3 and type(wood) == "number" and wood > 0 then
        self:notify(L("builder stokes the fire"), true)
        sm:set("stores.wood", wood - 1)
        sm:set("game.fire", { value = self:fire() + 1 })
    end
    if self:fire() > 0 then
        sm:set("game.fire", { value = self:fire() - 1 })
        self:onFireChange() -- 会重新安排 coolFire
    end
end

function Room:adjustTemp()
    local sm = self.engine.state
    local old = self:temp()
    if self:temp() > 0 and self:temp() > self:fire() then
        sm:set("game.temperature", { value = self:temp() - 1 })
        self:notify(L("the room is {0}", L(Room.TEMP[self:temp() + 1])), true)
    end
    if self:temp() < 4 and self:temp() < self:fire() then
        sm:set("game.temperature", { value = self:temp() + 1 })
        self:notify(L("the room is {0}", L(Room.TEMP[self:temp() + 1])), true)
    end
    if self:temp() ~= old then self.changed = true end
    self.tempTimer = self.engine:setTimeout(function() self:adjustTemp() end, Room.ROOM_WARM_DELAY)
end

-- BUILDER --------------------------------------------------------------------
function Room:unlockForest()
    self.engine.state:set("stores.wood", 4)
    self.engine:module("outside")
    self:notify(L("the wind howls outside"))
    self:notify(L("the wood is running out"))
end

function Room:updateBuilderState()
    local sm = self.engine.state
    local lb = self:builder()
    if lb == 0 then
        self:notify(L("a ragged stranger stumbles through the door and collapses in the corner"))
        lb = sm:setget("game.builder.level", 1)
        self.engine:setTimeout(function() self:unlockForest() end, Room.NEED_WOOD_DELAY)
    elseif lb < 3 and self:temp() >= 3 then
        if lb == 1 then
            self:notify(L("the stranger shivers, and mumbles quietly. her words are unintelligible."))
        elseif lb == 2 then
            self:notify(L("the stranger in the corner stops shivering. her breathing calms."))
        end
        lb = sm:setget("game.builder.level", lb + 1)
    end
    if lb < 3 then
        self.engine:setTimeout(function() self:updateBuilderState() end, Room.BUILDER_STATE_DELAY)
    end
end

-- BUILD / BUY ----------------------------------------------------------------
local function needsWorkshop(t) return t == "weapon" or t == "upgrade" or t == "tool" end

function Room:craftUnlocked(item, silent)
    local sm = self.engine.state
    if self.unlocked[item.name] then return true end
    if self:builder() < 4 then return false end
    if needsWorkshop(item.type) and sm:get('game.buildings["workshop"]', true) == 0 then return false end
    local cost = item.cost(sm)
    if sm:get('game.buildings["' .. item.name .. '"]', true) > 0 then
        self.unlocked[item.name] = true
        return true
    end
    -- 原版：至少有一半木头，且其它材料都见过
    if sm:get("stores.wood", true) < (cost.wood or 0) * 0.5 then return false end
    for c in pairs(cost) do
        if not sm:get('stores["' .. c .. '"]') then return false end
    end
    self.unlocked[item.name] = true
    if not silent and not sm:get('game.buildings["' .. item.name .. '"]') and item.availableMsg then
        self:notify(item.availableMsg)
    end
    return true
end

function Room:buyUnlocked(item)
    local sm = self.engine.state
    if self.unlocked[item.name] then return true end
    if sm:get('game.buildings["trading post"]', true) > 0 then
        if item.name == "compass" or sm:get('stores["' .. item.name .. '"]') ~= nil then return true end
    end
    return false
end

function Room:updateBuildButtons(silent)
    for _, item in ipairs(Items.Craftables) do self:craftUnlocked(item, silent) end
end

local function pay(self, cost)
    local sm = self.engine.state
    local mod = {}
    for k, n in pairs(cost) do
        local have = sm:get('stores["' .. k .. '"]', true)
        if have < n then
            self:notify(L("not enough " .. k))
            return false
        end
        mod[k] = have - n
    end
    sm:setM("stores", mod)
    return true
end

function Room:build(item)
    local sm = self.engine.state
    if self:temp() <= 1 then
        self:notify(L("builder just shivers"))
        return false
    end
    local n = math.max(Items.num(sm, item.name, item), 0)
    if item.maximum and item.maximum <= n then return false end
    if not pay(self, item.cost(sm)) then return false end
    self:notify(item.buildMsg)
    if item.type == "building" then
        sm:add('game.buildings["' .. item.name .. '"]', 1)
    else
        sm:add('stores["' .. item.name .. '"]', 1)
    end
    if item.maximum and n + 1 >= item.maximum and item.maxMsg then self:notify(item.maxMsg) end
end

function Room:buy(item)
    local sm = self.engine.state
    local n = math.max(Items.num(sm, item.name, item), 0)
    if item.maximum and item.maximum <= n then return false end
    if not pay(self, item.cost(sm)) then return false end
    if item.buildMsg then self:notify(item.buildMsg) end
    sm:add('stores["' .. item.name .. '"]', 1)
end

function Room:handleStateUpdates(e)
    local sm = self.engine.state
    if e.category == "stores" then
        self:updateBuildButtons()
        -- 原版 updateStoresView：拿到罗盘后开辟漫漫尘途
        if sm:get("stores.compass") and not self.engine.modules.path then
            self.engine:module("path"):announce()
        end
        -- 原版 updateStoresView：库存过多且已开放世界地图时，小偷出现
        if sm:get("game.thieves") == nil and sm:get("features.location.world") then
            for _, v in pairs(sm:get("stores") or {}) do
                if type(v) == "number" and v > 5000 then sm:startThieves() break end
            end
        end
    elseif type(e.stateName) == "string" and e.stateName:find("^game%.buildings") then
        self:updateBuildButtons()
    end
end

-- VIEW -----------------------------------------------------------------------
--- 库存与收入（原版 updateStoresView / updateIncomeView），返回文本行。
function Room:storesLines()
    local sm = self.engine.state
    local stores = sm:get("stores") or {}
    local income = {}
    for _, inc in pairs(sm:get("income") or {}) do
        for k, v in pairs(inc.stores or {}) do
            if v ~= 0 then
                income[k] = income[k] or { n = 0, delay = inc.delay }
                income[k].n = income[k].n + v
            end
        end
    end
    local groups = { res = {}, special = {}, weapon = {} }
    for k, v in pairs(stores) do
        if type(v) == "number" and not k:find("blueprint") then
            local item = Items.byName[k]
            local t = item and item.type
            if t ~= "upgrade" and t ~= "building" then
                local g = t == "weapon" and "weapon" or (t == "special" and "special" or "res")
                local line = L(k) .. "：" .. math.floor(v)
                local inc = income[k]
                if inc and inc.n ~= 0 then
                    line = line .. "  (" .. L("{0} per {1}s", (inc.n > 0 and "+" or "") .. inc.n, inc.delay or 10) .. ")"
                end
                table.insert(groups[g], line)
            end
        end
    end
    local lines = {}
    for _, g in ipairs({ { "res", L("stores") }, { "special", nil }, { "weapon", L("weapons") } }) do
        local list = groups[g[1]]
        if #list > 0 then
            table.sort(list)
            if g[2] then lines[#lines + 1] = "【" .. g[2] .. "】" end
            for _, l in ipairs(list) do lines[#lines + 1] = l end
        end
    end
    return lines
end

function Room:view()
    local engine, sm = self.engine, self.engine.state
    local buttons = {}
    local wood = sm:get("stores.wood")
    if self:fire() == 0 then
        buttons[#buttons + 1] = engine:button{ id = "stoke", text = L("light fire"), cooldown = Room.STOKE_COOLDOWN,
            cost = type(wood) == "number" and { wood = 5 } or nil, callback = function() return self:lightFire() end }
    else
        buttons[#buttons + 1] = engine:button{ id = "stoke", text = L("stoke fire"), cooldown = Room.STOKE_COOLDOWN,
            cost = type(wood) == "number" and { wood = 1 } or nil, callback = function() return self:stokeFire() end }
    end
    local function section(label, list, unlocked, act)
        local row = {}
        for _, item in ipairs(list) do
            if unlocked(item) then
                local max = item.maximum and Items.num(sm, item.name, item) + 1 > item.maximum
                row[#row + 1] = engine:button{ text = L(item.name), cost = item.cost(sm), enabled = not max,
                    callback = function() return act(item) end }
            end
        end
        if #row > 0 then
            buttons[#buttons + 1] = { label = label }
            for _, b in ipairs(row) do buttons[#buttons + 1] = b end
        end
    end
    section(L("build:"), Items.Craftables, function(i) return not needsWorkshop(i.type) and self.unlocked[i.name] end,
        function(i) return self:build(i) end)
    if sm:get('game.buildings["workshop"]', true) > 0 then
        section(L("craft:"), Items.Craftables, function(i) return needsWorkshop(i.type) and self.unlocked[i.name] end,
            function(i) return self:build(i) end)
    end
    if sm:get('game.buildings["trading post"]', true) > 0 then
        section(L("buy:"), Items.TradeGoods, function(i) return self:buyUnlocked(i) end, function(i) return self:buy(i) end)
    end
    return { title = self:locationName(), lines = self:storesLines(), buttons = buttons }
end

return Room
