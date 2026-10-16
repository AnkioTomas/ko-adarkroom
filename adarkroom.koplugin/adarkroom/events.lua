-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- Port of A Dark Room script/events.js (event framework, combat, loot).
--[[--
事件：事件池里每个事件 { title, isAvailable(engine), scenes = { start = {...}, ... } }。
场景字段：text{}、notification、onLoad(engine)、reward{}、buttons{ id = { text, cost?, reward?,
available?(engine), notification?, onChoose?(engine), nextScene = "end" | { [概率上界] = 场景名 } } }。
buttons 是有序数组形式 { { id = "kill", ... }, ... }，保证按钮顺序稳定（原版靠 JS 对象插入顺序）。
每 3–6 分钟随机触发一个可用事件；没有可用事件则半程后重试。
--]]
local L = require("adarkroom.l10n")
local Items = require("adarkroom.items")

local Events = {}
Events.__index = Events

Events.EVENT_TIME_RANGE = { 3, 6 } -- 分钟
Events.delayState = "wait"
Events.EAT_COOLDOWN = 5
Events.MEDS_COOLDOWN = 7
Events.HYPO_COOLDOWN = 7
Events.LEAVE_COOLDOWN = 1
Events.STUN_DURATION = 4   -- 秒
Events.FIGHT_SPEED = 0.1   -- 秒：胜利后到结算的停顿
Events.LOG_LINES = 6       -- 战斗记录保留条数

function Events.new(engine)
    return setmetatable({ engine = engine, stack = {}, pool = {} }, Events)
end

function Events:init()
    self.pool = {}
    for _, mod in ipairs({ "global", "room", "outside" }) do
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

function Events:encounters() return require("adarkroom.events.encounters") end
function Events:setpiece(name) return require("adarkroom.events.setpieces")[name] end

function Events:activeEvent() return self.stack[1] end
function Events:inWorld() return self.engine.activeModule ~= nil and self.engine.activeModule.name == "world" end

function Events:scheduleNextEvent(scale)
    local lo, hi = Events.EVENT_TIME_RANGE[1], Events.EVENT_TIME_RANGE[2]
    local minutes = math.floor(math.random() * (hi - lo)) + lo
    if scale and scale > 0 then minutes = minutes * scale end
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

function Events:triggerFight()
    local possible = {}
    for _, f in ipairs(self:encounters()) do
        if f.isAvailable(self.engine) then possible[#possible + 1] = f end
    end
    if #possible > 0 then self:startEvent(possible[math.random(#possible)]) end
end

function Events:startEvent(event)
    if not event then return end
    table.insert(self.stack, 1, { def = event, scene = nil })
    self:loadScene("start")
end

function Events:switchEvent(event)
    if not event then return end
    self:abortCombat()
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
    active.loot = nil
    local sm = self.engine.state
    if scene.onLoad then scene.onLoad(self.engine) end
    if scene.notification then self.engine:notify(nil, scene.notification) end
    if scene.reward then sm:addM("stores", scene.reward) end
    if scene.combat then
        self:startCombat(scene)
    elseif scene.loot then
        active.loot = self:rollLoot(scene.loot)
    end
    self.engine:requestRender()
end

-- STORES (库存 / 远征背包) ---------------------------------------------------------
function Events:getQuantity(store)
    local world = self.engine.modules.world
    if store == "water" and world and self:inWorld() then return world.water end
    if store == "hp" and world and self:inWorld() then return world.health end
    local n
    if self:inWorld() then
        n = self.engine.modules.path:outfit()[store]
    else
        n = self.engine.state:get('stores["' .. store .. '"]', true)
    end
    if type(n) ~= "number" or n ~= n or n < 0 then return 0 end
    return n
end

function Events:canAfford(info)
    for store, n in pairs(info.cost or {}) do
        if self:getQuantity(store) < n then return false end
    end
    return true
end

function Events:pay(cost)
    local engine, sm = self.engine, self.engine.state
    local world = engine.modules.world
    local mod = {}
    for store, n in pairs(cost) do
        if store == "water" and self:inWorld() then world:setWater(world.water - n)
        elseif store == "hp" and self:inWorld() then world:setHp(world.health - n)
        else mod[store] = -n end
    end
    if self:inWorld() then
        local outfit = engine.modules.path:outfit()
        for k, v in pairs(mod) do outfit[k] = (outfit[k] or 0) + v end
    else
        sm:addM("stores", mod)
    end
end

function Events:buttonClick(info)
    local sm = self.engine.state
    if info.cost then
        if not self:canAfford(info) then return false end
        self:pay(info.cost)
    end
    if info.onChoose then info.onChoose(self.engine) end
    if info.onClick then info.onClick(self.engine) end
    if info.reward then sm:addM("stores", info.reward) end
    if info.notification then self.engine:notify(nil, info.notification) end
    if info.nextEvent then
        local nextDef = self:setpiece(info.nextEvent)
        if nextDef then return self:switchEvent(nextDef) end
    end
    local ns = info.nextScene
    if ns == "end" then
        return self:endEvent()
    elseif type(ns) == "string" then
        return self:loadScene(ns)
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
    self:abortCombat()
    table.remove(self.stack, 1)
    self.engine:requestRender()
end

-- COMBAT ---------------------------------------------------------------------
--[[ 原版是实时战斗：敌人按 attackDelay 秒出手，玩家按钮各有冷却。这里保留实时节奏，
     只在出手、命中等事件发生时刷新界面（电子墨水屏不做逐秒倒计时）。 ]]

function Events:fightLog(msg)
    local f = self.fight
    if not f then return end
    table.insert(f.log, 1, msg)
    while #f.log > Events.LOG_LINES do table.remove(f.log) end
end

function Events:startCombat(scene)
    local world = self.engine.modules.world
    self.fight = {
        scene = scene, enemyHp = scene.health, enemyMax = scene.health,
        stunnedUntil = 0, won = false, fought = false, log = {},
    }
    self:fightLog(scene.notification or "")
    self.fight.attackTimer = self.engine:setTimeout(function() self:enemyAttack() end, scene.attackDelay)
    if not world or not world.health then return end
end

function Events:abortCombat()
    local f = self.fight
    if f then
        f.fought = true
        if f.attackTimer then self.engine:clearTimeout(f.attackTimer) end
        self.fight = nil
    end
end

function Events:enemyAttack()
    local f = self.fight
    if not f or f.won or f.fought then return end
    local engine, world = self.engine, self.engine.modules.world
    local scene = f.scene
    if engine:now() >= f.stunnedUntil then
        local toHit = scene.hit * (engine.state:hasPerk("evasive") and 0.8 or 1)
        local name = scene.enemyName or L(scene.enemy or "")
        if math.random() <= toHit then
            world:setHp(world.health - scene.damage)
            self:fightLog(name .. " -" .. scene.damage)
        else
            self:fightLog(name .. " " .. L("miss"))
        end
        if world.health <= 0 then
            self:endEvent()
            world:die()
            return
        end
    end
    f.attackTimer = engine:setTimeout(function() self:enemyAttack() end, scene.attackDelay)
    engine:requestRender()
end

--- 当前可用的武器（原版 startCombat 的计数逻辑：带了伤害型或弹药足够的武器才算，否则给拳头）
function Events:weaponList()
    local World = require("adarkroom.world")
    local outfit = self.engine.modules.path:outfit()
    local list, usable = {}, 0
    for _, k in ipairs(World.WEAPON_ORDER) do
        local w = World.Weapons[k]
        if k ~= "fists" and type(outfit[k]) == "number" and outfit[k] > 0 then
            local counts = type(w.damage) == "number" and w.damage > 0
            for c, n in pairs(w.cost or {}) do
                if (outfit[c] or 0) < n then counts = false end
            end
            if counts then usable = usable + 1 end
            list[#list + 1] = k
        end
    end
    if usable == 0 then table.insert(list, 1, "fists") end
    return list
end

function Events:useWeapon(name)
    local f = self.fight
    if not f or f.won then return false end
    local World = require("adarkroom.world")
    local engine, sm, world = self.engine, self.engine.state, self.engine.modules.world
    local weapon = World.Weapons[name]
    local outfit = engine.modules.path:outfit()
    if weapon.type == "unarmed" then
        sm:add("character.punches", 1)
        local p = sm:get("character.punches", true)
        if p == 50 and not sm:hasPerk("boxer") then sm:addPerk("boxer")
        elseif p == 150 and not sm:hasPerk("martial artist") then sm:addPerk("martial artist")
        elseif p == 300 and not sm:hasPerk("unarmed master") then sm:addPerk("unarmed master") end
    end
    if weapon.cost then
        for k, n in pairs(weapon.cost) do
            if (outfit[k] or 0) < n then return false end
        end
        for k, n in pairs(weapon.cost) do outfit[k] = outfit[k] - n end
    end
    local dmg = -1
    if math.random() <= world:getHitChance() then
        dmg = weapon.damage
        if type(dmg) == "number" then
            if weapon.type == "unarmed" and sm:hasPerk("boxer") then dmg = dmg * 2 end
            if weapon.type == "unarmed" and sm:hasPerk("martial artist") then dmg = dmg * 3 end
            if weapon.type == "unarmed" and sm:hasPerk("unarmed master") then dmg = dmg * 2 end
            if weapon.type == "melee" and sm:hasPerk("barbarian") then dmg = math.floor(dmg * 1.5) end
        end
    end
    if dmg == "stun" then
        f.stunnedUntil = engine:now() + Events.STUN_DURATION
        self:fightLog("@ " .. weapon.verb .. "：" .. L("stunned"))
    elseif dmg < 0 then
        self:fightLog("@ " .. weapon.verb .. "：" .. L("miss"))
    else
        f.enemyHp = math.max(0, f.enemyHp - dmg)
        self:fightLog("@ " .. weapon.verb .. " -" .. dmg)
    end
    if f.enemyHp <= 0 and not f.won then
        f.won = true
        self:winFight()
    end
end

function Events:doHeal(item, amount)
    local world = self.engine.modules.world
    local outfit = self.engine.modules.path:outfit()
    if (outfit[item] or 0) > 0 and world.health < world:getMaxHealth() then
        outfit[item] = outfit[item] - 1
        world:setHp(math.min(world:getMaxHealth(), world.health + amount))
        self:fightLog("@ +" .. amount)
        return true
    end
    return false
end

function Events:winFight()
    local f = self.fight
    self.engine:setTimeout(function()
        if not self.fight or self.fight ~= f or f.fought then return end
        f.fought = true
        if f.attackTimer then self.engine:clearTimeout(f.attackTimer) end
        local active = self:activeEvent()
        active.loot = self:rollLoot(f.scene.loot or {})
        active.won = f.scene.deathMessage or ""
        self.fight = nil
        self.engine:requestRender()
    end, Events.FIGHT_SPEED)
end

-- LOOT -----------------------------------------------------------------------
function Events:rollLoot(lootList)
    local rows = {}
    local names = {}
    for k in pairs(lootList) do names[#names + 1] = k end
    table.sort(names)
    for _, k in ipairs(names) do
        local loot = lootList[k]
        if math.random() < loot.chance then
            local num = math.floor(math.random() * (loot.max - loot.min)) + loot.min
            if num > 0 then rows[#rows + 1] = { name = k, left = num } end
        end
    end
    return rows
end

--- 拿一件；放不下返回 false（原版会弹出丢弃菜单，这里直接置灰，见 README）
function Events:takeOne(row)
    local Path = require("adarkroom.path")
    local path = self.engine.modules.path
    if row.left <= 0 or Path.getWeight(row.name) > path:getFreeSpace() then return false end
    local outfit = path:outfit()
    row.left = row.left - 1
    outfit[row.name] = (outfit[row.name] or 0) + 1
    return true
end

function Events:takeAll(row)
    while self:takeOne(row) do end
end

function Events:lootButtons(active)
    local Path = require("adarkroom.path")
    local path = self.engine.modules.path
    local buttons = {}
    local any = false
    for _, row in ipairs(active.loot or {}) do
        if row.left > 0 then
            local fits = Path.getWeight(row.name) <= path:getFreeSpace()
            any = any or fits
            buttons[#buttons + 1] = {
                { text = L(row.name) .. " [" .. row.left .. "]", enabled = fits,
                  callback = function() self:takeOne(row) self.engine:requestRender() end },
                { text = L("take") .. " " .. L("all"), enabled = fits,
                  callback = function() self:takeAll(row) self.engine:requestRender() end },
            }
        end
    end
    if #buttons > 0 then
        table.insert(buttons, 1, { label = L("take:") })
        buttons[#buttons + 1] = { text = L("take everything"), enabled = any, callback = function()
            for _, row in ipairs(active.loot) do self:takeAll(row) end
            self.engine:requestRender()
        end }
    end
    return buttons
end

-- VIEW -----------------------------------------------------------------------
local function costText(info)
    if info.cost and next(info.cost) then return info.text .. "（" .. Items.costText(info.cost) .. "）" end
    return info.text
end

function Events:combatView(active)
    local engine, world, f = self.engine, self.engine.modules.world, self.fight
    local World = require("adarkroom.world")
    local scene = f.scene
    local lines = {
        "@  " .. world.health .. "/" .. world:getMaxHealth(),
        (scene.chara or "?") .. "  " .. f.enemyHp .. "/" .. f.enemyMax .. "  " .. (scene.enemyName or L(scene.enemy or "")),
        "",
    }
    for _, l in ipairs(f.log) do lines[#lines + 1] = l end
    local outfit = engine.modules.path:outfit()
    local attack = {}
    for _, k in ipairs(self:weaponList()) do
        local w = World.Weapons[k]
        local cd = w.cooldown
        if w.type == "unarmed" and engine.state:hasPerk("unarmed master") then cd = cd / 2 end
        local ok = true
        for c, n in pairs(w.cost or {}) do if (outfit[c] or 0) < n then ok = false end end
        attack[#attack + 1] = engine:button{ id = "atk_" .. k, text = w.verb, cooldown = cd, cost = w.cost, enabled = ok,
            callback = function() return self:useWeapon(k) end }
    end
    local canHeal = world.health < world:getMaxHealth()
    local heal = {
        engine:button{ id = "eat", text = L("eat meat"), cooldown = Events.EAT_COOLDOWN, cost = { ["cured meat"] = 1 },
            enabled = canHeal and (outfit["cured meat"] or 0) > 0,
            callback = function() return self:doHeal("cured meat", world:meatHeal()) end },
    }
    if (outfit.medicine or 0) ~= 0 then
        heal[#heal + 1] = engine:button{ id = "meds", text = L("use meds"), cooldown = Events.MEDS_COOLDOWN,
            cost = { medicine = 1 }, enabled = canHeal,
            callback = function() return self:doHeal("medicine", world:medsHeal()) end }
    end
    return { title = active.def.title, lines = lines, buttons = { attack, heal }, is_event = true }
end

--- 当前事件的界面描述；没有事件返回 nil。
function Events:view()
    local active = self:activeEvent()
    if not active then return nil end
    if self.fight then return self:combatView(active) end
    local engine = self.engine
    local scene = active.def.scenes[active.scene]
    local lines = {}
    if scene.combat then
        lines[#lines + 1] = active.won or ""
    else
        for _, t in ipairs(scene.text or {}) do lines[#lines + 1] = t end
    end
    local buttons = self:lootButtons(active)
    if scene.combat and not scene.buttons then
        buttons[#buttons + 1] = engine:button{ id = "ev_leave", text = L("leave"), cooldown = Events.LEAVE_COOLDOWN,
            callback = function()
                if scene.nextScene and scene.nextScene ~= "end" then self:loadScene(scene.nextScene) else self:endEvent() end
            end }
    end
    for _, info in ipairs(scene.buttons or {}) do
        local enabled = self:canAfford(info)
        if info.available and not info.available(engine) then enabled = false end
        buttons[#buttons + 1] = engine:button{ id = info.cooldown and ("ev_" .. info.id) or nil, text = costText(info),
            cooldown = info.cooldown, enabled = enabled, callback = function() return self:buttonClick(info) end }
    end
    return { title = active.def.title, lines = lines, buttons = buttons, is_event = true }
end

-- DELAYED EVENTS (state "wait") ----------------------------------------------
--- 原版把回调的 eval 路径（如 'Room[4].scenes.wood100.action'）存进 wait，读档时 eval。
--- 这里改成注册表：Events.delayed[action] = function(engine)，事件模块加载时登记；
--- 剩余秒数存 wait.<净化后的 key>，动作名存 wait_action.<key>。
Events.delayed = {}

local function delayKey(action) return (action:gsub("[^%w]", "_")) end

function Events:saveDelay(action, delay)
    local sm = self.engine.state
    local key = delayKey(action)
    local path = Events.delayState .. "." .. key
    if delay then
        sm:set(path, delay)
        sm:set(Events.delayState .. "_action." .. key, action, true)
    end
    local function tick()
        local left = sm:get(path, true) - 1
        if left <= 0 then
            sm:remove(path, true)
            sm:remove(Events.delayState .. "_action." .. key, true)
            local fn = Events.delayed[action]
            if fn then fn(self.engine) end
        else
            sm:set(path, left, true)
            self.engine:setTimeout(tick, 1)
        end
    end
    self.engine:setTimeout(tick, 1)
end

function Events:initDelay()
    local sm = self.engine.state
    local waits = sm:get(Events.delayState)
    local actions = sm:get(Events.delayState .. "_action") or {}
    if type(waits) ~= "table" then return end
    for key, left in pairs(waits) do
        if type(left) == "number" and left > 0 and actions[key] then self:saveDelay(actions[key]) end
    end
end

return Events
