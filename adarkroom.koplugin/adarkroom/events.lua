-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- Port of A Dark Room script/events.js (event framework; combat/loot arrive in batch 4).
--[[--
事件：事件池里每个事件 { title, isAvailable(engine), scenes = { start = {...}, ... } }。
场景字段：text{}、notification、onLoad(engine)、reward{}、buttons{ id = { text, cost?, reward?,
available?(engine), notification?, onChoose?(engine), nextScene = "end" | { [概率上界] = 场景名 } } }。
buttons 是有序数组形式 { { id = "kill", ... }, ... }，保证按钮顺序稳定（原版靠 JS 对象插入顺序）。
每 3–6 分钟随机触发一个可用事件；没有可用事件则半程后重试。
--]]
local L = require("adarkroom.l10n")

local Events = {}
Events.__index = Events

Events.EVENT_TIME_RANGE = { 3, 6 } -- 分钟
Events.delayState = "wait"

function Events.new(engine)
    return setmetatable({ engine = engine, stack = {}, pool = {} }, Events)
end

function Events:init()
    self.pool = {}
    for _, mod in ipairs({ "global" }) do -- room / outside / marketing 在第 3 批加入
        local ok, list = pcall(require, "adarkroom.events." .. mod)
        if ok then
            for _, e in ipairs(list) do self.pool[#self.pool + 1] = e end
        else
            self.engine:log("event module " .. mod .. " failed: " .. tostring(list))
        end
    end
    self.stack = {}
    self:scheduleNextEvent()
    self:initDelay()
end

function Events:activeEvent() return self.stack[1] end

function Events:scheduleNextEvent(scale)
    local lo, hi = Events.EVENT_TIME_RANGE[1], Events.EVENT_TIME_RANGE[2]
    local minutes = math.floor(math.random() * (hi - lo)) + lo
    if scale and scale > 0 then minutes = minutes * scale end
    self.engine:log("next event scheduled in " .. minutes .. " minutes")
    self.timer = self.engine:setTimeout(function() self:triggerEvent() end, minutes * 60)
end

function Events:triggerEvent()
    if self:activeEvent() == nil then
        local possible = {}
        for _, e in ipairs(self.pool) do
            if e.isAvailable(self.engine) then possible[#possible + 1] = e end
        end
        if #possible == 0 then
            self:scheduleNextEvent(0.5)
            return
        end
        self:startEvent(possible[math.random(#possible)])
    end
    self:scheduleNextEvent()
end

function Events:startEvent(event)
    if not event then return end
    table.insert(self.stack, 1, { def = event, scene = nil })
    self:loadScene("start")
end

function Events:switchEvent(event)
    if not event then return end
    table.remove(self.stack, 1)
    self:startEvent(event)
end

function Events:loadScene(name)
    local active = self:activeEvent()
    local scene = active.def.scenes[name]
    if not scene then
        self.engine:log("ERROR: no scene " .. tostring(name))
        return self:endEvent()
    end
    active.scene = name
    local sm = self.engine.state
    if scene.onLoad then scene.onLoad(self.engine) end
    if scene.notification then self.engine:notify(nil, scene.notification) end
    if scene.reward then sm:addM("stores", scene.reward) end
    if scene.combat then
        -- 战斗在第 4 批实现；先跳过，避免事件卡死
        self.engine:log("combat scene not yet supported")
        return self:endEvent()
    end
    self.engine:requestRender()
end

function Events:getQuantity(store)
    local n = self.engine.state:get('stores["' .. store .. '"]', true)
    if type(n) ~= "number" or n ~= n or n < 0 then return 0 end
    return n
end

function Events:canAfford(info)
    for store, n in pairs(info.cost or {}) do
        if self:getQuantity(store) < n then return false end
    end
    return true
end

function Events:buttonClick(info)
    local sm = self.engine.state
    if info.cost then
        if not self:canAfford(info) then return end
        local mod = {}
        for store, n in pairs(info.cost) do mod[store] = -n end
        sm:addM("stores", mod)
    end
    if info.onChoose then info.onChoose(self.engine) end
    if info.reward then sm:addM("stores", info.reward) end
    if info.notification then self.engine:notify(nil, info.notification) end
    if info.nextEvent and self.registry and self.registry[info.nextEvent] then
        return self:switchEvent(self.registry[info.nextEvent])
    end
    local ns = info.nextScene
    if ns == "end" then
        return self:endEvent()
    elseif type(ns) == "table" then
        local r = math.random()
        local lowest
        for key in pairs(ns) do
            local p = tonumber(key)
            if p and r < p and (lowest == nil or p < lowest) then lowest = p end
        end
        if lowest then return self:loadScene(ns[lowest] or ns[tostring(lowest)]) end
        self.engine:log("ERROR: no suitable scene found")
        return self:endEvent()
    end
    self.engine:requestRender()
end

function Events:endEvent()
    table.remove(self.stack, 1)
    self.engine:requestRender()
end

--- 当前事件的界面描述；没有事件返回 nil。
function Events:view()
    local active = self:activeEvent()
    if not active then return nil end
    local scene = active.def.scenes[active.scene]
    local lines = {}
    for _, t in ipairs(scene.text or {}) do lines[#lines + 1] = t end
    local buttons = {}
    for _, info in ipairs(scene.buttons or {}) do
        local enabled = self:canAfford(info)
        if info.available and not info.available(self.engine) then enabled = false end
        local text = info.text
        if info.cost then
            local parts = {}
            for store, n in pairs(info.cost) do parts[#parts + 1] = L(store) .. " " .. n end
            table.sort(parts)
            text = text .. "（" .. table.concat(parts, "，") .. "）"
        end
        buttons[#buttons + 1] = { text = text, enabled = enabled, callback = function() self:buttonClick(info) end }
    end
    return { title = active.def.title, lines = lines, buttons = buttons, is_event = true }
end

-- DELAYED EVENTS (state "wait") ----------------------------------------------
--- 原版用 action 名字符串存到 wait.<stateName>，读档时 eval 回调。这里改成注册表：
--- Events.delayed[action] = function(engine) ... end，由各模块在加载时登记。
Events.delayed = {}

function Events:saveDelay(action, stateName, delay)
    local sm = self.engine.state
    local path = Events.delayState .. "." .. stateName
    if delay then
        sm:set(path, delay)
    else
        delay = sm:get(path, true)
    end
    local function tick()
        local left = sm:get(path, true) - 1
        if left <= 0 then
            sm:remove(path)
            local fn = Events.delayed[action]
            if fn then fn(self.engine) end
        else
            sm:set(path, left, true)
            self.engine:setTimeout(tick, 1)
        end
    end
    sm:set(Events.delayState .. "_action." .. stateName, action, true)
    self.engine:setTimeout(tick, 1)
end

function Events:initDelay()
    local sm = self.engine.state
    local waits = sm:get(Events.delayState)
    local actions = sm:get(Events.delayState .. "_action") or {}
    if type(waits) ~= "table" then return end
    for stateName, left in pairs(waits) do
        if type(left) == "number" and actions[stateName] then
            self:saveDelay(actions[stateName], stateName)
        end
    end
end

return Events
