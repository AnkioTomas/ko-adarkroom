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
Engine.PAGE_ROWS = 8       -- 每页按钮行数（不含翻页行与导航行），可用设置 page_rows 覆盖

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
    local self = setmetatable({ host = host, timers = {}, modules = {}, order = {}, running = false }, Engine)
    L.load(host:getSetting("locale", "zh_cn"))
    self.Perks = {}
    for k, p in pairs(Engine.Perks) do
        self.Perks[k] = { name = L(p.name), desc = L(p.desc), notify = L(p.notify) }
    end
    self.dispatch = Dispatch.new()
    local tree, note = State.migrate(host:loadState())
    self.state = State.new(self, tree)
    self.notifications = Notifications.new(self)
    self.dispatch:subscribe("stateUpdate", function() self:requestRender() end)
    if note then self:log(note) end
    self.events = require("adarkroom.events").new(self)
    self.cooling = {}
    local now = self:now()
    for id, left in pairs(self.state:get("cooldown") or {}) do
        if type(left) == "number" and left > 0 then self.cooling[id] = now + left end
    end
    return self
end

--- 秒级时钟；测试宿主可提供 host:now() 注入虚拟时间。
function Engine:now()
    if type(self.host.now) == "function" then return self.host:now() end
    return os.time()
end

-- COOLDOWNS (port of script/Button.js cooldown) -------------------------------
function Engine:cooldownLeft(id)
    local ends = self.cooling[id]
    if not ends then return 0 end
    local left = ends - self:now()
    if left <= 0 then self.cooling[id] = nil return 0 end
    return math.ceil(left)
end

function Engine:startCooldown(id, seconds)
    if not seconds or seconds <= 0 then return end
    self.cooling[id] = self:now() + seconds
    self:setTimeout(function() self:requestRender() end, seconds)
end

function Engine:clearCooldown(id) self.cooling[id] = nil end

--- 生成带冷却的按钮。opts = { id, text, cooldown, cost?, enabled?, callback }。
--- callback 返回 false 表示动作失败（原版 Button.clearCooldown），不进入冷却。
function Engine:button(opts)
    local left = opts.id and self:cooldownLeft(opts.id) or 0
    local text = opts.text
    if opts.cost and next(opts.cost) then
        text = text .. "（" .. require("adarkroom.items").costText(opts.cost) .. "）"
    end
    if left > 0 then text = text .. " · " .. left .. "s" end
    return {
        text = text,
        enabled = left == 0 and opts.enabled ~= false,
        callback = function()
            if opts.id and self:cooldownLeft(opts.id) > 0 then return end
            if opts.callback() ~= false and opts.id then self:startCooldown(opts.id, opts.cooldown) end
            self:requestRender()
        end,
    }
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
    if self.gameOver then return end -- 通关后存档已清（只留声望），不要再写回
    self.state.tree.port_version = State.PORT_VERSION
    local cd = {}
    for id in pairs(self.cooling) do
        local left = self:cooldownLeft(id)
        if left > 0 then cd[id] = left end
    end
    self.state.tree.cooldown = cd
    local world = self.modules.world
    self.state.tree.expedition = world and world:snapshot() or nil
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
    local buttons = self:paginate(view.title or "", view.buttons or {})
    if not view.is_event then
        local nav = {}
        for _, name in ipairs(self.order) do
            local m = self.modules[name]
            if m ~= self.activeModule and not m.hidden and not (self.activeModule and self.activeModule.hidden) then
                nav[#nav + 1] = { text = "→ " .. m:locationName(), callback = function() self:travelTo(m) end }
            end
        end
        nav[#nav + 1] = { text = L("exit"), callback = function() self:close() end }
        buttons[#buttons + 1] = nav
    end
    self.host:showScreen{
        title = view.title, lines = lines, buttons = buttons, map = view.map,
        on_close = function() self:close() end, -- 标题栏关闭按钮
    }
end

--- 按钮项排成行（连续的单个按钮两两并排），超过一页时分页并加翻页行。
--- 页码按界面标题记忆；电子墨水屏上不做滚动条，翻页即整屏重绘。
function Engine:paginate(key, items)
    local rows, pending = {}, nil
    local function flush()
        if pending then rows[#rows + 1] = { pending } pending = nil end
    end
    for _, b in ipairs(items) do
        if b.label then
            flush()
            rows[#rows + 1] = b
        elseif b[1] then
            flush()
            rows[#rows + 1] = b
        elseif pending then
            rows[#rows + 1] = { pending, b }
            pending = nil
        else
            pending = b
        end
    end
    flush()
    local per = self.host:getSetting("page_rows", Engine.PAGE_ROWS)
    if type(per) ~= "number" or per < 2 then per = Engine.PAGE_ROWS end
    if #rows <= per then return rows end
    self.pages = self.pages or {}
    local pages = math.ceil(#rows / per)
    local page = math.max(1, math.min(self.pages[key] or 1, pages))
    self.pages[key] = page
    local out = {}
    for i = (page - 1) * per + 1, math.min(#rows, page * per) do out[#out + 1] = rows[i] end
    -- 分组标题落在页尾时没有意义，挪到下一页
    if out[#out] and out[#out].label and page < pages then out[#out] = nil end
    out[#out + 1] = {
        -- pager 字段给能画专用翻页条的宿主界面用（月读 Pager）；通用界面把它当三个按钮画
        pager = { page = page, pages = pages,
            prev = function() self.pages[key] = page - 1 self:requestRender() end,
            next = function() self.pages[key] = page + 1 self:requestRender() end },
        { text = "‹", enabled = page > 1, callback = function() self.pages[key] = page - 1 self:requestRender() end },
        { text = page .. " / " .. pages, enabled = false, callback = function() end },
        { text = "›", enabled = page < pages, callback = function() self.pages[key] = page + 1 self:requestRender() end },
    }
    return out
end

--- 原版 Prestige.collectStores（被毁村庄的地标）。
function Engine:prestigeCollect()
    require("adarkroom.prestige").collectStores(self)
end

--- 原版 Engine.deleteSave(true)：清空存档但保留声望（previous.*）。通关时调用。
function Engine:deleteSave()
    local Prestige = require("adarkroom.prestige")
    local prestige = Prestige.get(self)
    self:clearAllTimers()
    self.saveTimer, self.renderPending = nil, false
    self.cooling = {}
    self.host:saveState({ port_version = State.PORT_VERSION, previous = { stores = prestige.stores, score = prestige.score } })
    self.gameOver = true
end

--- 结局里的「重新开始」：丢掉当前引擎，用同一宿主读取（只剩声望的）存档开新局。
function Engine:restart()
    self.running, self.visible = false, false
    self:clearAllTimers()
    local fresh = Engine.new(self.host)
    fresh.game = self.game
    if self.game then self.game.engine = fresh end
    fresh:start()
    return fresh
end

-- MODULES --------------------------------------------------------------------
function Engine:register(module)
    if not self.modules[module.name] then self.order[#self.order + 1] = module.name end
    self.modules[module.name] = module
    return module
end

--- 已注册则返回现有实例，否则 require("adarkroom.<name>").new(engine) 并注册。
function Engine:module(name)
    return self.modules[name] or self:register(require("adarkroom." .. name).new(self))
end

function Engine:travelTo(module)
    if self.activeModule == module then return end
    self.activeModule = module
    self.notifications:printQueue(module)
    if module.onArrival then module:onArrival() end
    self:requestRender()
end

-- LIFECYCLE ------------------------------------------------------------------
function Engine:start()
    self.running = true
    self.visible = true
    local room = self:module("room")
    if self.state:get("features.location.outside") then self:module("outside") end
    if self.state:get("features.location.path") or self.state:get("stores.compass") then self:module("path") end
    if self.state:get("features.location.fabricator") then self:module("fabricator") end
    if self.state:get("features.location.spaceShip") or self.state:get("game.foundShip") then self:module("ship") end
    local snap = self.state:get("expedition")
    self.events:init()
    for id in pairs(self.cooling) do
        local left = self:cooldownLeft(id)
        if left > 0 then self:setTimeout(function() self:requestRender() end, left) end
    end
    self:incomeTick()
    if type(snap) == "table" and self.modules.world then
        -- 远征途中关闭过插件：回到地图上继续
        self.modules.world:resume(snap)
        self.activeModule = self.modules.world
    else
        self:travelTo(room)
    end
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
