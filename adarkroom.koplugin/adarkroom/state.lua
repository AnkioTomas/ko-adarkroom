-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- Port of A Dark Room script/state_manager.js (original by Michael Galusha).
--[[--
状态树（原版 $SM）。路径写法同原版："stores.wood"、'stores["wood"]'、"income['thieves']"。
set/add 等修改后标脏并发布 stateUpdate { category, stateName }；存盘由 engine 合并延迟执行。
原版用 eval 访问 State，这里按路径逐层走表。
--]]
local State = {}
State.__index = State

State.MAX_STORE = 99999999999999
State.VERSION = 1.3        -- 上游存档版本
State.PORT_VERSION = 2     -- 本移植的存档结构版本（1 = 第 1 批演示存档）

State.CATEGORIES = {
    "features", "stores", "character", "income", "timers", "game",
    "playStats", "previous", "outfit", "config", "wait", "cooldown",
}

local function split(path)
    local words = {}
    for w in tostring(path):gmatch("[^%.%[%]'\"]+") do
        words[#words + 1] = tonumber(w) and #w > 0 and w:match("^%d+$") and tonumber(w) or w
    end
    return words
end
State.split = split

local function category(path)
    return split(path)[1] or "all"
end

--- @param engine table 需要 engine:log / engine:requestSave / engine.dispatch
function State.new(engine, tree)
    local self = setmetatable({ engine = engine, tree = tree or {} }, State)
    for _, c in ipairs(State.CATEGORIES) do
        if type(self.tree[c]) ~= "table" then self.tree[c] = {} end
    end
    return self
end

function State:log(msg) if self.engine then self.engine:log(msg) end end

function State:fireUpdate(stateName, save)
    local cat = stateName and category(stateName) or "all"
    if self.engine then
        if save then self.engine:requestSave() end
        self.engine.dispatch:publish("stateUpdate", { category = cat, stateName = stateName or "all" })
    end
end

function State:_changed(stateName, noEvent)
    if not noEvent then
        if self.engine then self.engine:requestSave() end
        self:fireUpdate(stateName)
    end
end

function State:get(stateName, requestZero)
    local obj = self.tree
    for _, w in ipairs(split(stateName)) do
        if type(obj) ~= "table" then obj = nil break end
        obj = obj[w]
    end
    if requestZero and (not obj or (type(obj) == "table" and next(obj) == nil)) then return 0 end
    return obj
end

function State:set(stateName, value, noEvent)
    local words = split(stateName)
    if #words == 0 then return end
    if type(value) == "number" and value > State.MAX_STORE then value = State.MAX_STORE end
    local obj = self.tree
    for i = 1, #words - 1 do
        local w = words[i]
        if type(obj[w]) ~= "table" then obj[w] = {} end
        obj = obj[w]
    end
    obj[words[#words]] = value
    if words[1] == "stores" and type(value) == "number" and value < 0 then
        obj[words[#words]] = 0
        self:log("WARNING: state:" .. stateName .. " can not be a negative value. Set to 0 instead.")
    end
    self:_changed(stateName, noEvent)
end

function State:setM(parentName, list, noEvent)
    if self:get(parentName) == nil then self:set(parentName, {}, true) end
    for k, v in pairs(list) do self:set(parentName .. '["' .. k .. '"]', v, true) end
    self:_changed(parentName, noEvent)
end

--- @return integer 1 表示原值不是数字
function State:add(stateName, value, noEvent)
    local old = self:get(stateName, true)
    if old ~= old then
        self:log("WARNING: " .. stateName .. " was corrupted (NaN). Resetting to 0.")
        self:set(stateName, value, noEvent)
    elseif type(old) ~= "number" or type(value) ~= "number" then
        self:log("WARNING: Can not do math with state:" .. stateName)
        return 1
    else
        self:set(stateName, old + value, noEvent)
    end
    return 0
end

function State:addM(parentName, list, noEvent)
    local err = 0
    if self:get(parentName) == nil then self:set(parentName, {}, true) end
    for k, v in pairs(list) do err = err + self:add(parentName .. '["' .. k .. '"]', v, true) end
    self:_changed(parentName, noEvent)
    return err
end

function State:setget(stateName, value, noEvent)
    self:set(stateName, value, noEvent)
    return self:get(stateName)
end

function State:remove(stateName, noEvent)
    local words = split(stateName)
    local obj = self.tree
    for i = 1, #words - 1 do
        obj = type(obj) == "table" and obj[words[i]] or nil
    end
    if type(obj) == "table" and obj[words[#words]] ~= nil then
        obj[words[#words]] = nil
    else
        self:log("WARNING: Tried to remove non-existant state '" .. stateName .. "'.")
    end
    self:_changed(stateName, noEvent)
end

function State:removeBranch(stateName, noEvent)
    local branch = self:get(stateName)
    if type(branch) == "table" then
        for k, v in pairs(branch) do
            if type(v) == "table" then self:removeBranch(stateName .. '["' .. k .. '"]', true) end
        end
        if next(branch) == nil then self:remove(stateName, true) end
    end
    self:_changed(stateName, noEvent)
end

-- PERKS ----------------------------------------------------------------------
function State:addPerk(name)
    self:set('character.perks["' .. name .. '"]', true)
    local perk = self.engine and self.engine.Perks and self.engine.Perks[name]
    if perk and perk.notify then self.engine:notify(nil, perk.notify) end
end

function State:hasPerk(name)
    return self:get('character.perks["' .. name .. '"]') and true or false
end

-- INCOME ---------------------------------------------------------------------
function State:setIncome(source, options)
    local existing = self:get('income["' .. source .. '"]')
    if type(existing) == "table" then options.timeLeft = existing.timeLeft end
    self:set('income["' .. source .. '"]', options)
end

function State:getIncome(source)
    return self:get('income["' .. source .. '"]') or {}
end

function State:addStolen(stores)
    for k, v in pairs(stores) do
        local old = self:get('stores["' .. k .. '"]', true)
        local short = old + v
        if short < 0 then
            self:add('game.stolen["' .. k .. '"]', (v * -1) + short)
        else
            self:add('game.stolen["' .. k .. '"]', v * -1)
        end
    end
end

--- 每秒调用一次（engine 负责定时）。返回是否有变化。
function State:collectIncome()
    local income = self:get("income")
    if type(income) ~= "table" then return false end
    local changed = false
    for source, inc in pairs(income) do
        if type(inc.timeLeft) ~= "number" then inc.timeLeft = 0 end
        inc.timeLeft = inc.timeLeft - 1
        if inc.timeLeft <= 0 then
            if source == "thieves" then self:addStolen(inc.stores) end
            local ok = true
            if source ~= "thieves" then
                for k, v in pairs(inc.stores or {}) do
                    if self:get('stores["' .. k .. '"]', true) + v < 0 then ok = false break end
                end
            end
            if ok then self:addM("stores", inc.stores or {}, true) end
            changed = true
            if type(inc.delay) == "number" then inc.timeLeft = inc.delay end
        end
    end
    if changed then self:fireUpdate("income", true) end
    return changed
end

-- MIGRATION ------------------------------------------------------------------
--- 把任意旧存档变成当前结构。raw 可以是 nil、第 1 批演示存档 { fire, wood, log } 或本结构。
function State.migrate(raw)
    if type(raw) ~= "table" then return {}, "new" end
    local note
    if raw.port_version == nil and raw.fire ~= nil and raw.features == nil then
        -- 第 1 批：{ fire = 0..4, wood = n, log = {...} }
        raw = {
            stores = { wood = tonumber(raw.wood) or 0 },
            game = { fire = { value = tonumber(raw.fire) or 0 }, temperature = { value = 0 } },
            features = { location = { room = true } },
            notifications = type(raw.log) == "table" and raw.log or nil,
        }
        note = "migrated batch-1 save"
    end
    raw.version = raw.version or State.VERSION
    raw.port_version = State.PORT_VERSION
    return raw, note
end

return State
