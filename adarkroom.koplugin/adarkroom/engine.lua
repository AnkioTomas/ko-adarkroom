-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- Port of A Dark Room script/engine.js (core parts: timers, save/load, modules, perks).
--[[--
引擎：持有 host、状态树、通知、事件；所有定时器经 engine:setTimeout 走 host.schedule，
close() 时统一取消（KOReader 不在后台跑游戏，界面关掉时间就停）。
渲染：活动事件优先，否则当前模块的 view()，下面附通知日志。
--]]
local Dispatch = require("adarkroom.dispatch")
local L = require("adarkroom.l10n")
local Notifications = require("adarkroom.notifications")
local State = require("adarkroom.state")

local Engine = {}
Engine.__index = Engine

Engine.SAVE_DELAY = 1      -- 秒：合并多次修改后再写盘
Engine.INCOME_TICK = 1     -- 秒：原版 collectIncome 每秒一次

-- 原版 Engine.Perks（文字在第 4 批战斗时用到，先全部带上）
Engine.Perks = {
    boxer = { name = "boxer", desc = "punches do more damage", notify = "learned to throw punches with purpose" },
    martial_artist = { name = "martial artist", desc = "punches do even more damage.", notify = "learned to fight quite effectively without weapons" },
    unarmed_master = { name = "unarmed master", desc = "punch twice as fast, and with even more force", notify = "learned to strike faster without weapons" },
    barbarian = { name = "barbarian", desc = "melee weapons deal more damage", notify = "learned to swing weapons with force" },
    slow_metabolism = { name = "slow metabolism", desc = "go twice as far without eating", notify = "learned how to ignore the hunger" },
    desert_rat = { name = "desert rat", desc = "go twice as far without drinking", notify = "learned to love the dry air" },
    evasive = { name = "evasive", desc = "dodge attacks more effectively", notify = "learned to be where they're not" },
    precise = { name = "precise", desc = "land blows more often", notify = "learned to predict their movement" },
    scout = { name = "scout", desc = "see farther", notify = "learned to look ahead" },
    stealthy = { name = "stealthy", desc = "better avoid conflict in the wild", notify = "learned how not to be seen" },
    gastronome = { name = "gastronome", desc = "restore more health when eating", notify = "learned to make the most of food" },
}

function Engine.new(host)
    local self = setmetatable({ host = host, timers = {}, modules = {}, running = false }, Engine)
    L.load(host:getSetting("locale", "zh_cn"))
    self.Perks = {}
    for k, p in pairs(Engine.Perks) do
        self.Perks[k] = { name = L(p.name), desc = L(p.desc), notify = L(p.notify) }
    end
    self.dispatch = Dispatch.new()
    local tree, note = State.migrate(host:loadState())
    self.state = State.new(self, tree)
    self.notifications = Notifications.new(self)
    if note then self:log(note) end
    self.events = require("adarkroom.events").new(self)
    return self
end

function Engine:log(msg)
    local ok, logger = pcall(require, "logger")
    if ok and logger then logger.dbg("adarkroom:", msg) end
end

-- TIMERS ---------------------------------------------------------------------
--- @return function 句柄，可交给 clearTimeout
function Engine:setTimeout(fn, seconds)
    local handle
    handle = function()
        self.timers[handle] = nil
        if self.running then fn() end
    end
    self.timers[handle] = true
    self.host:schedule(seconds, handle)
    return handle
end

function Engine:clearTimeout(handle)
    if handle and self.timers[handle] then
        self.timers[handle] = nil
        self.host:unschedule(handle)
    end
end

function Engine:clearAllTimers()
    for h in pairs(self.timers) do self.host:unschedule(h) end
    self.timers = {}
end

-- SAVE -----------------------------------------------------------------------
function Engine:requestSave()
    if self.saveTimer or not self.running then return end
    self.saveTimer = self:setTimeout(function()
        self.saveTimer = nil
        self:saveGame()
    end, Engine.SAVE_DELAY)
end

function Engine:saveGame()
    self.state.tree.port_version = State.PORT_VERSION
    self.host:saveState(self.state.tree)
end

-- NOTIFY / RENDER ------------------------------------------------------------
function Engine:notify(module, text, noQueue)
    self.notifications:notify(module, text, noQueue)
end

--- 合并同一轮内的多次刷新请求。
function Engine:requestRender()
    if self.renderPending or not self.visible then return end
    self.renderPending = true
    self:setTimeout(function()
        self.renderPending = false
        self:render()
    end, 0)
end

function Engine:render()
    if not self.visible then return end
    local view = self.events:view() or (self.activeModule and self.activeModule:view()) or { title = L("A Dark Room") }
    local lines = {}
    for _, l in ipairs(view.lines or {}) do lines[#lines + 1] = l end
    if not view.is_event then
        local msgs = self.notifications:messages()
        if #msgs > 0 then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "────────"
            for _, m in ipairs(msgs) do lines[#lines + 1] = m end
        end
    end
    local buttons = {}
    for _, b in ipairs(view.buttons or {}) do buttons[#buttons + 1] = b end
    if not view.is_event then
        buttons[#buttons + 1] = { text = L("exit") == "exit" and "退出" or L("exit"), callback = function() self:close() end }
    end
    self.host:showScreen{
        title = view.title, lines = lines, buttons = buttons,
        on_close = function() self:close() end, -- 标题栏关闭按钮
    }
end

-- MODULES --------------------------------------------------------------------
function Engine:register(module)
    self.modules[module.name] = module
    return module
end

function Engine:travelTo(module)
    if self.activeModule == module then return end
    self.activeModule = module
    if module.onArrival then module:onArrival() end
    self.notifications:printQueue(module)
    self:requestRender()
end

-- LIFECYCLE ------------------------------------------------------------------
function Engine:start()
    self.running = true
    self.visible = true
    local room = self:register(require("adarkroom.room").new(self))
    self.events:init()
    self:incomeTick()
    self:travelTo(room)
    self:render()
    return self
end

function Engine:incomeTick()
    self.incomeTimer = self:setTimeout(function()
        self.state:collectIncome()
        self:incomeTick()
    end, Engine.INCOME_TICK)
end

function Engine:close()
    if not self.running then return end
    self:saveGame()
    self.running = false
    self.visible = false
    self:clearAllTimers()
    self.host:closeScreen()
end

return Engine
