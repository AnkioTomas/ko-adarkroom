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
function Events:setpiece(name)
    return require("adarkroom.events.setpieces")[name] or require("adarkroom.events.executioner")[name]
end

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
     只在出手、命中等事件发生时刷新界面（电子墨水屏不做逐秒倒计时）。
     状态（原版 setStatus）：shield 护盾（下一次受击改为回血，然后破碎）、enraged 狂暴（4 秒内
     每 0.5 秒出手）、meditation 冥想（5 秒内不出手、伤害全部蓄积，下一次出手一次性打出）、
     energised 充能（下一击 ×4）、venomous 剧毒（下一击附带每秒 dmg/2 的持续伤害）、
     boost 强化（玩家 3 秒内武器冷却减半）。 ]]

Events.SHIELD_COOLDOWN = 10
Events.STIM_COOLDOWN = 10
Events.ENERGISE_MULTIPLIER = 4
Events.EXPLOSION_DURATION = 3
Events.ENRAGE_DURATION = 4
Events.MEDITATE_DURATION = 5
Events.BOOST_DURATION = 3
Events.BOOST_DAMAGE = 10
Events.DOT_TICK = 1

function Events:fightLog(msg)
    local f = self.fight
    if not f then return end
    table.insert(f.log, 1, msg)
    while #f.log > Events.LOG_LINES do table.remove(f.log) end
end

--- 绑定在当前战斗上的定时器：战斗结束（clearTimeouts）时一并取消，过期回调直接丢弃。
function Events:fightTimer(fn, seconds)
    local f = self.fight
    if not f then return end
    local h
    h = self.engine:setTimeout(function()
        f.timers[h] = nil
        if self.fight == f and not f.fought then fn() end
    end, seconds)
    f.timers[h] = true
    return h
end

function Events:clearTimeouts()
    local f = self.fight
    if not f then return end
    for h in pairs(f.timers) do self.engine:clearTimeout(h) end
    f.timers = {}
    f.attackTimer, f.dotTimer = nil, nil
end

function Events:enemyName()
    local scene = self.fight.scene
    return scene.enemyName or L(scene.enemy or "")
end

function Events:startCombat(scene)
    self.fight = {
        scene = scene, enemyHp = scene.health, enemyMax = scene.health,
        stunnedUntil = 0, won = false, fought = false, log = {}, timers = {}, meditateDmg = 0,
        enemy = { side = "enemy", status = "none" }, player = { side = "player", status = "none" },
    }
    self:fightLog(scene.notification or "")
    self:startEnemyAttacks()
    for _, sp in ipairs(scene.specials or {}) do self:scheduleSpecial(sp) end
end

--- 原版 setInterval(s.action, s.delay)：敌人的周期技能（护盾 / 充能 / 狂暴 …）
function Events:scheduleSpecial(sp)
    local f = self.fight
    self:fightTimer(function()
        if f.won then return end
        local text = sp.action(self.engine, f.enemy)
        if text then self:fightLog(self:enemyName() .. "：" .. L(text)) end
        self:scheduleSpecial(sp)
        self.engine:requestRender()
    end, sp.delay)
end

function Events:startEnemyAttacks(delay)
    local f = self.fight
    if not f then return end
    if f.attackTimer then self.engine:clearTimeout(f.attackTimer) f.timers[f.attackTimer] = nil end
    local d = delay or f.scene.attackDelay
    f.attackTimer = self:fightTimer(function()
        f.attackTimer = nil
        self:enemyAttack()
        if self.fight == f and not f.won and not f.fought and not f.attackTimer then self:startEnemyAttacks(delay) end
    end, d)
end

function Events:setStatus(fighter, status)
    local f = self.fight
    fighter.status = status
    if not f then return end
    if status == "enraged" and fighter.side == "enemy" then
        self:startEnemyAttacks(0.5)
        self:fightTimer(function()
            fighter.status = "none"
            self:startEnemyAttacks()
        end, Events.ENRAGE_DURATION)
    elseif status == "meditation" then
        f.meditateDmg = 0
        self:fightTimer(function() fighter.status = "none" end, Events.MEDITATE_DURATION)
    elseif status == "boost" then
        self:fightTimer(function() fighter.status = "none" self.engine:requestRender() end, Events.BOOST_DURATION)
    end
end

function Events:abortCombat()
    local f = self.fight
    if f then
        self:clearTimeouts()
        f.fought = true
        self.fight = nil
    end
end

--- 打到目标身上，返回飘字文本。hp 改动经 world:setHp（玩家）或 f.enemyHp（敌人）。
function Events:damage(attacker, target, dmg)
    local f = self.fight
    local world = self.engine.modules.world
    local shielded = target.status == "shield"
    local energised = attacker.status == "energised"
    local venomous = attacker.status == "venomous"
    local meditating = target.status == "meditation"
    local msg = ""
    if type(dmg) == "number" then
        if dmg < 0 then
            msg = L("miss")
        else
            if energised then dmg = dmg * Events.ENERGISE_MULTIPLIER end
            if meditating then
                f.meditateDmg = (f.meditateDmg or 0) + dmg
                msg = tostring(dmg)
            else
                msg = (shielded and "+" or "-") .. dmg
                local delta = shielded and dmg or -dmg
                if target.side == "enemy" then
                    f.enemyHp = math.min(f.enemyMax, math.max(0, f.enemyHp + delta))
                else
                    world:setHp(math.min(world:getMaxHealth(), math.max(0, world.health + delta)))
                end
            end
            if venomous and not shielded then
                if f.dotTimer then self.engine:clearTimeout(f.dotTimer) f.timers[f.dotTimer] = nil end
                local dot = math.floor(dmg / 2)
                local function tick()
                    f.dotTimer = self:fightTimer(function()
                        self:dotDamage(target, dot)
                        if self.fight == f and not f.fought then tick() end
                    end, Events.DOT_TICK)
                end
                tick()
            end
            if shielded then target.status = "none" end -- 护盾挨一下就碎
        end
    elseif dmg == "stun" then
        msg = L("stunned")
        if target.side == "enemy" then f.stunnedUntil = self.engine:now() + Events.STUN_DURATION end
    end
    if energised or venomous then attacker.status = "none" end -- 增益只管一击
    return msg
end

function Events:dotDamage(target, dmg)
    local f = self.fight
    local world = self.engine.modules.world
    if target.side == "player" then
        world:setHp(math.max(0, world.health - dmg))
        self:fightLog("@ -" .. dmg)
        self:checkPlayerDeath()
    else
        f.enemyHp = math.max(0, f.enemyHp - dmg)
        self:fightLog(self:enemyName() .. " -" .. dmg)
        if f.enemyHp <= 0 and not f.won then
            f.won = true
            self:winFight()
        end
    end
    self.engine:requestRender()
end

function Events:checkPlayerDeath()
    local world = self.engine.modules.world
    if world.health <= 0 then
        self:clearTimeouts()
        self:endEvent()
        world:die()
        return true
    end
    return false
end

function Events:enemyAttack()
    local f = self.fight
    if not f or f.won or f.fought then return end
    local engine, scene = self.engine, f.scene
    local stunned = engine:now() < f.stunnedUntil
    if not stunned and f.enemy.status ~= "meditation" then
        local toHit = scene.hit * (engine.state:hasPerk("evasive") and 0.8 or 1)
        local dmg = -1
        if (f.meditateDmg or 0) > 0 then
            dmg = f.meditateDmg
            f.meditateDmg = 0
        elseif math.random() <= toHit then
            dmg = scene.damage
        end
        self:fightLog(self:enemyName() .. " " .. self:damage(f.enemy, f.player, dmg))
        if self:checkPlayerDeath() then return end
    end
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
    self:fightLog("@ " .. weapon.verb .. " " .. self:damage(f.player, f.enemy, dmg))
    -- 原版 atHealth：血量跌破阈值时触发一次
    if type(dmg) == "number" and dmg > 0 then
        for k, action in pairs(f.scene.atHealth or {}) do
            local th = tonumber(k)
            if th and f.enemyHp <= th and f.enemyHp + dmg > th then
                local text = action(engine, f.enemy)
                if text then self:fightLog(self:enemyName() .. "：" .. L(text)) end
            end
        end
    end
    if f.enemyHp <= 0 and not f.won then
        f.won = true
        if f.scene.explosion then self:explode(f.scene.explosion) else self:winFight() end
    end
end

--- 原版 explode：敌人死后 3 秒自爆，炸到玩家（护盾同样有效），活下来才算赢。
function Events:explode(dmg)
    local f = self.fight
    self:clearTimeouts()
    self:fightLog(self:enemyName() .. " *")
    self:fightTimer(function()
        self:fightLog("* " .. self:damage(f.enemy, f.player, dmg))
        if not self:checkPlayerDeath() then self:winFight() end
        self.engine:requestRender()
    end, Events.EXPLOSION_DURATION)
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

function Events:useShield()
    local f = self.fight
    if not f or f.won then return false end
    f.player.status = "shield"
    self:fightLog("@ " .. L("shield"))
end

function Events:useStim()
    local f = self.fight
    if not f or f.won then return false end
    self:setStatus(f.player, "boost")
    self:fightLog("@ " .. L("boost"))
    self:dotDamage(f.player, Events.BOOST_DAMAGE)
end

function Events:winFight()
    local f = self.fight
    self:clearTimeouts()
    self.engine:setTimeout(function()
        if not self.fight or self.fight ~= f or f.fought then return end
        f.fought = true
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

--- 拿一件；放不下返回 false（界面上会改为弹出丢弃菜单，见 dropMenu）
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

--- 原版 drawDrop：背包放不下时，列出为腾出空间各需丢掉多少件（每种物品一项）。
function Events:dropOptions(row)
    local Path = require("adarkroom.path")
    local path = self.engine.modules.path
    local weight, free = Path.getWeight(row.name), path:getFreeSpace()
    local opts = {}
    local outfit = path:outfit()
    local names = {}
    for k in pairs(outfit) do names[#names + 1] = k end
    table.sort(names)
    for _, k in ipairs(names) do
        local w = Path.getWeight(k)
        if k ~= row.name and w > 0 and (outfit[k] or 0) > 0 then
            local num = math.min(math.ceil((weight - free) / w), outfit[k])
            if num > 0 then opts[#opts + 1] = { name = k, num = num } end
        end
    end
    return opts
end

--- 原版 dropStuff：丢下的东西放回战利品列表，然后拿起原本想拿的那件。
function Events:dropStuff(active, row, opt)
    local outfit = self.engine.modules.path:outfit()
    local target
    for _, r in ipairs(active.loot) do if r.name == opt.name then target = r end end
    if target then target.left = target.left + opt.num
    else active.loot[#active.loot + 1] = { name = opt.name, left = opt.num } end
    outfit[opt.name] = outfit[opt.name] - opt.num
    self:takeOne(row)
end

function Events:dropView(active)
    local row = active.dropFor
    local buttons = { { label = L("drop:") } }
    for _, opt in ipairs(self:dropOptions(row)) do
        buttons[#buttons + 1] = { text = L(opt.name) .. " x" .. opt.num, callback = function()
            active.dropFor = nil
            self:dropStuff(active, row, opt)
            self.engine:requestRender()
        end }
    end
    buttons[#buttons + 1] = { text = L("nothing"), callback = function()
        active.dropFor = nil
        self.engine:requestRender()
    end }
    local path = self.engine.modules.path
    return {
        title = active.def.title,
        lines = { L(row.name) .. " [" .. row.left .. "]", L("free {0}/{1}", math.floor(path:getFreeSpace()), path:getCapacity()) },
        buttons = buttons, is_event = true,
    }
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
                { text = L(row.name) .. " [" .. row.left .. "]",
                  callback = function()
                      if not self:takeOne(row) and #self:dropOptions(row) > 0 then active.dropFor = row end
                      self.engine:requestRender()
                  end },
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

local STATUS = { shield = "shield", enraged = "enraged", meditation = "meditation", energised = "energised",
    venomous = "venomous", boost = "boost" }
local function statusText(st)
    if st and STATUS[st] then return " [" .. L(STATUS[st]) .. "]" end
    return ""
end

function Events:combatView(active)
    local engine, world, f = self.engine, self.engine.modules.world, self.fight
    local World = require("adarkroom.world")
    local scene = f.scene
    local lines = {
        "@  " .. world.health .. "/" .. world:getMaxHealth() .. statusText(f.player.status),
        (scene.chara or "?") .. "  " .. f.enemyHp .. "/" .. f.enemyMax .. "  " .. self:enemyName() .. statusText(f.enemy.status),
        "",
    }
    for _, l in ipairs(f.log) do lines[#lines + 1] = l end
    local outfit = engine.modules.path:outfit()
    local boosted = f.player.status == "boost"
    local attack = {}
    for _, k in ipairs(self:weaponList()) do
        local w = World.Weapons[k]
        local cd = w.cooldown
        if w.type == "unarmed" and engine.state:hasPerk("unarmed master") then cd = cd / 2 end
        if boosted then cd = cd / 2 end
        local ok = true
        for c, n in pairs(w.cost or {}) do if (outfit[c] or 0) < n then ok = false end end
        attack[#attack + 1] = engine:button{ id = "atk_" .. k, text = w.verb, cooldown = cd, cost = w.cost, enabled = ok and not f.won,
            callback = function() return self:useWeapon(k) end }
    end
    local canHeal = world.health < world:getMaxHealth() and not f.won
    local heal = {
        engine:button{ id = "eat", text = L("eat meat"), cooldown = Events.EAT_COOLDOWN, cost = { ["cured meat"] = 1 },
            enabled = canHeal and (outfit["cured meat"] or 0) > 0,
            callback = function() return self:doHeal("cured meat", world:meatHeal()) end },
    }
    if (outfit.medicine or 0) ~= 0 then
        heal[#heal + 1] = engine:button{ id = "meds", text = L("use meds"), cooldown = Events.MEDS_COOLDOWN,
            cost = { medicine = 1 }, enabled = canHeal and (outfit.medicine or 0) > 0,
            callback = function() return self:doHeal("medicine", world:medsHeal()) end }
    end
    if (outfit.hypo or 0) ~= 0 then
        heal[#heal + 1] = engine:button{ id = "hypo", text = L("use hypo"), cooldown = Events.HYPO_COOLDOWN,
            cost = { hypo = 1 }, enabled = canHeal and (outfit.hypo or 0) > 0,
            callback = function() return self:doHeal("hypo", world:hypoHeal()) end }
    end
    local extra = {}
    -- 原版：兴奋剂按钮只看背包里有没有，使用时并不消耗（照搬）
    if (outfit.stim or 0) > 0 then
        extra[#extra + 1] = engine:button{ id = "stim", text = L("boost"), cooldown = Events.STIM_COOLDOWN,
            enabled = not f.won, callback = function() return self:useStim() end }
    end
    if engine.state:get('stores["kinetic armour"]', true) > 0 then
        extra[#extra + 1] = engine:button{ id = "shld", text = L("shield"), cooldown = Events.SHIELD_COOLDOWN,
            enabled = not f.won, callback = function() return self:useShield() end }
    end
    local buttons = { attack, heal }
    if #extra > 0 then buttons[#buttons + 1] = extra end
    return { title = active.def.title, lines = lines, buttons = buttons, is_event = true }
end

--- 原版：背包里有发光石时事件按钮不再花火把。
function Events:effectiveCost(info)
    if not info.cost then return nil end
    local outfit = self:inWorld() and self.engine.modules.path:outfit() or {}
    if (outfit.glowstone or 0) > 0 and info.cost.torch then
        local c = {}
        for k, v in pairs(info.cost) do if k ~= "torch" then c[k] = v end end
        return c
    end
    return info.cost
end

--- 当前事件的界面描述；没有事件返回 nil。
function Events:view()
    local active = self:activeEvent()
    if not active then return nil end
    if self.fight then return self:combatView(active) end
    if active.dropFor then return self:dropView(active) end
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
    for _, orig in ipairs(scene.buttons or {}) do
        local cost = self:effectiveCost(orig)
        local info = orig
        if cost ~= orig.cost then
            info = setmetatable({ cost = cost }, { __index = orig })
        end
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
