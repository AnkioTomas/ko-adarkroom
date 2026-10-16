-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- Port of A Dark Room script/outside.js.
local L = require("adarkroom.l10n")

local Outside = {}
Outside.__index = Outside

Outside.GATHER_DELAY = 60
Outside.TRAPS_DELAY = 90
Outside.POP_DELAY = { 0.5, 3 } -- 分钟
Outside.HUT_ROOM = 4

-- 有序：显示顺序 gatherer 在前，其余按原版定义顺序
Outside.INCOME = {
    { name = "gatherer", delay = 10, stores = { wood = 1 } },
    { name = "hunter", delay = 10, stores = { fur = 0.5, meat = 0.5 } },
    { name = "trapper", delay = 10, stores = { meat = -1, bait = 1 } },
    { name = "tanner", delay = 10, stores = { fur = -5, leather = 1 } },
    { name = "charcutier", delay = 10, stores = { meat = -5, wood = -5, ["cured meat"] = 1 } },
    { name = "iron miner", delay = 10, stores = { ["cured meat"] = -1, iron = 1 } },
    { name = "coal miner", delay = 10, stores = { ["cured meat"] = -1, coal = 1 } },
    { name = "sulphur miner", delay = 10, stores = { ["cured meat"] = -1, sulphur = 1 } },
    { name = "steelworker", delay = 10, stores = { iron = -1, coal = -1, steel = 1 } },
    { name = "armourer", delay = 10, stores = { steel = -1, sulphur = -1, bullets = 1 } },
}

Outside.TrapDrops = {
    { rollUnder = 0.5, name = "fur", message = L("scraps of fur") },
    { rollUnder = 0.75, name = "meat", message = L("bits of meat") },
    { rollUnder = 0.85, name = "scales", message = L("strange scales") },
    { rollUnder = 0.93, name = "teeth", message = L("scattered teeth") },
    { rollUnder = 0.995, name = "cloth", message = L("tattered cloth") },
    { rollUnder = 1.0, name = "charm", message = L("a crudely made charm") },
}

Outside.JOBS = {
    lodge = { "hunter", "trapper" }, tannery = { "tanner" }, smokehouse = { "charcutier" },
    ["iron mine"] = { "iron miner" }, ["coal mine"] = { "coal miner" }, ["sulphur mine"] = { "sulphur miner" },
    steelworks = { "steelworker" }, armoury = { "armourer" },
}

function Outside.new(engine)
    local self = setmetatable({ engine = engine, name = "outside" }, Outside)
    local sm = engine.state
    if sm:get("features.location.outside") == nil then
        sm:set("features.location.outside", true)
        if not sm:get("game.buildings") then sm:set("game.buildings", {}) end
        if not sm:get("game.population") then sm:set("game.population", 0) end
        if not sm:get("game.workers") then sm:set("game.workers", {}) end
    end
    engine.dispatch:subscribe("stateUpdate", function(e) self:handleStateUpdates(e) end)
    self:updateVillage()
    self:updateVillageIncome()
    return self
end

function Outside:notify(text, noQueue) self.engine:notify(self, text, noQueue) end

function Outside:locationName()
    local huts = self.engine.state:get('game.buildings["hut"]', true)
    if huts == 0 then return L("A Silent Forest")
    elseif huts == 1 then return L("A Lonely Hut")
    elseif huts <= 4 then return L("A Tiny Village")
    elseif huts <= 8 then return L("A Modest Village")
    elseif huts <= 14 then return L("A Large Village") end
    return L("A Raucous Village")
end

-- POPULATION -----------------------------------------------------------------
function Outside:getMaxPopulation()
    return self.engine.state:get('game.buildings["hut"]', true) * Outside.HUT_ROOM
end

function Outside:increasePopulation()
    local sm = self.engine.state
    local space = self:getMaxPopulation() - sm:get("game.population", true)
    if space > 0 then
        local num = math.floor(math.random() * (space / 2) + space / 2)
        if num == 0 then num = 1 end
        if num == 1 then self.engine:notify(nil, L("a stranger arrives in the night"))
        elseif num < 5 then self.engine:notify(nil, L("a weathered family takes up in one of the huts."))
        elseif num < 10 then self.engine:notify(nil, L("a small group arrives, all dust and bones."))
        elseif num < 30 then self.engine:notify(nil, L("a convoy lurches in, equal parts worry and hope."))
        else self.engine:notify(nil, L("the town's booming. word does get around.")) end
        sm:add("game.population", num)
    end
    self:schedulePopIncrease()
end

function Outside:schedulePopIncrease()
    local lo, hi = Outside.POP_DELAY[1], Outside.POP_DELAY[2]
    local minutes = math.floor(math.random() * (hi - lo)) + lo
    self.popTimer = self.engine:setTimeout(function() self:increasePopulation() end, minutes * 60)
end

function Outside:getNumGatherers()
    local sm = self.engine.state
    local num = sm:get("game.population", true)
    for _, n in pairs(sm:get("game.workers") or {}) do num = num - n end
    return num
end

function Outside:killVillagers(num)
    local sm = self.engine.state
    sm:add("game.population", -num)
    if sm:get("game.population", true) < 0 then sm:set("game.population", 0) end
    local remaining = self:getNumGatherers()
    if remaining < 0 then
        local gap = -remaining
        for _, job in ipairs(Outside.INCOME) do
            local path = 'game.workers["' .. job.name .. '"]'
            local n = sm:get(path)
            if type(n) == "number" then
                if n < gap then
                    gap = gap - n
                    sm:set(path, 0)
                else
                    sm:add(path, -gap)
                    break
                end
            end
        end
    end
end

function Outside:destroyHuts(num, allowEmpty)
    local sm = self.engine.state
    local dead = 0
    for _ = 1, num do
        local population = sm:get("game.population", true)
        local rate = population / Outside.HUT_ROOM
        local full = math.floor(rate)
        local huts = allowEmpty and sm:get('game.buildings["hut"]', true) or math.ceil(rate)
        if huts == 0 then break end
        local target = math.floor(math.random() * huts) + 1
        local inhabitants = 0
        if target <= full then inhabitants = Outside.HUT_ROOM
        elseif target == full + 1 then inhabitants = population % Outside.HUT_ROOM end
        sm:set('game.buildings["hut"]', sm:get('game.buildings["hut"]', true) - 1)
        if inhabitants > 0 then
            self:killVillagers(inhabitants)
            dead = dead + inhabitants
        end
    end
    return dead
end

-- WORKERS ----------------------------------------------------------------------
function Outside:checkWorker(building)
    local sm = self.engine.state
    local added = false
    for _, job in ipairs(Outside.JOBS[building] or {}) do
        if type(sm:get('game.buildings["' .. building .. '"]')) == "number"
            and type(sm:get('game.workers["' .. job .. '"]')) ~= "number" then
            sm:set('game.workers["' .. job .. '"]', 0)
            added = true
        end
    end
    return added
end

function Outside:increaseWorker(job, amt)
    local free = self:getNumGatherers()
    if free > 0 then self.engine.state:add('game.workers["' .. job .. '"]', math.min(free, amt)) end
end

function Outside:decreaseWorker(job, amt)
    local sm = self.engine.state
    local n = sm:get('game.workers["' .. job .. '"]', true)
    if n > 0 then sm:add('game.workers["' .. job .. '"]', -math.min(n, amt)) end
end

function Outside:updateVillageIncome()
    local sm = self.engine.state
    for _, job in ipairs(Outside.INCOME) do
        local num = job.name == "gatherer" and self:getNumGatherers() or sm:get('game.workers["' .. job.name .. '"]')
        if type(num) == "number" then
            if num < 0 then num = 0 end
            local stores, needsUpdate = {}, false
            local cur = sm:getIncome(job.name).stores or {}
            for k, v in pairs(job.stores) do
                stores[k] = v * num
                if cur[k] ~= stores[k] then needsUpdate = true end
            end
            if needsUpdate then sm:setIncome(job.name, { delay = job.delay, stores = stores }) end
        end
    end
end

function Outside:updateVillage()
    local sm = self.engine.state
    for k in pairs(sm:get("game.buildings") or {}) do
        if k ~= "trap" then self:checkWorker(k) end
    end
    if sm:get('game.buildings["hut"]', true) > 0 and not self.popTimer then
        self:schedulePopIncrease()
    end
end

function Outside:handleStateUpdates(e)
    local name = type(e.stateName) == "string" and e.stateName or ""
    if e.category == "stores" or name:find("^game%.buildings") then
        self:updateVillage()
    elseif name:find("^game%.workers") or name:find("^game%.population") then
        self:updateVillage()
        self:updateVillageIncome()
    end
end

-- ACTIONS --------------------------------------------------------------------
function Outside:onArrival()
    local sm = self.engine.state
    if not sm:get("game.outside.seenForest") then
        self:notify(L("the sky is grey and the wind blows relentlessly"))
        sm:set("game.outside.seenForest", true)
    end
    self:updateVillage()
end

function Outside:gatherWood()
    self:notify(L("dry brush and dead branches litter the forest floor"))
    local amt = self.engine.state:get('game.buildings["cart"]', true) > 0 and 50 or 10
    self.engine.state:add("stores.wood", amt)
end

function Outside:checkTraps()
    local sm = self.engine.state
    local drops, msg = {}, {}
    local numTraps = sm:get('game.buildings["trap"]', true)
    local numBait = sm:get("stores.bait", true)
    local numDrops = numTraps + (numBait < numTraps and numBait or numTraps)
    for _ = 1, numDrops do
        local roll = math.random()
        for _, drop in ipairs(Outside.TrapDrops) do
            if roll < drop.rollUnder then
                if drops[drop.name] == nil then
                    drops[drop.name] = 0
                    msg[#msg + 1] = drop.message
                end
                drops[drop.name] = drops[drop.name] + 1
                break
            end
        end
    end
    local s = L("the traps contain ")
    for i, m in ipairs(msg) do
        if #msg > 1 and i > 1 and i < #msg then s = s .. ", " end
        if #msg > 1 and i == #msg then s = s .. L(" and ") end
        s = s .. m
    end
    drops.bait = -(numBait < numTraps and numBait or numTraps)
    self:notify(s)
    sm:addM("stores", drops)
end

-- VIEW -----------------------------------------------------------------------
function Outside:view()
    local engine, sm = self.engine, self.engine.state
    local lines = {}
    -- 村落（原版 updateVillage 的建筑列表）
    local blds = sm:get("game.buildings") or {}
    local names = {}
    for k, n in pairs(blds) do if type(n) == "number" and n > 0 then names[#names + 1] = k end end
    table.sort(names, function(a, b) return L(a) < L(b) end)
    if #names > 0 or sm:get('game.buildings["hut"]', true) > 0 then
        lines[#lines + 1] = "【" .. L("village") .. "】  " .. L("pop ") .. sm:get("game.population", true) .. "/" .. self:getMaxPopulation()
        for _, k in ipairs(names) do
            if k == "trap" then
                local traps, bait = blds.trap, sm:get("stores.bait", true)
                local plain = math.max(traps - bait, 0)
                if plain > 0 then lines[#lines + 1] = L("trap") .. "：" .. plain end
                local baited = math.min(bait, traps)
                if baited > 0 then lines[#lines + 1] = L("baited trap") .. "：" .. baited end
            else
                lines[#lines + 1] = L(k) .. "：" .. blds[k]
            end
        end
    end
    local room = engine.modules.room
    if room then
        lines[#lines + 1] = ""
        for _, l in ipairs(room:storesLines()) do lines[#lines + 1] = l end
    end

    local buttons = {
        engine:button{ id = "gather", text = L("gather wood"), cooldown = Outside.GATHER_DELAY,
            callback = function() return self:gatherWood() end },
    }
    if sm:get('game.buildings["trap"]', true) > 0 then
        buttons[#buttons + 1] = engine:button{ id = "traps", text = L("check traps"), cooldown = Outside.TRAPS_DELAY,
            callback = function() return self:checkTraps() end }
    end
    -- 工人（原版 updateWorkersView）：每个工种一行「名称 数量 −10 −1 +1 +10」
    if sm:get("game.population", true) > 0 then
        buttons[#buttons + 1] = { label = L("gatherer") .. " " .. self:getNumGatherers() }
        local free = self:getNumGatherers()
        for _, job in ipairs(Outside.INCOME) do
            local n = sm:get('game.workers["' .. job.name .. '"]')
            if job.name ~= "gatherer" and type(n) == "number" then
                buttons[#buttons + 1] = {
                    { text = L(job.name) .. " " .. n, enabled = false, callback = function() end },
                    { text = "−10", enabled = n > 0, callback = function() self:decreaseWorker(job.name, 10) end },
                    { text = "−1", enabled = n > 0, callback = function() self:decreaseWorker(job.name, 1) end },
                    { text = "+1", enabled = free > 0, callback = function() self:increaseWorker(job.name, 1) end },
                    { text = "+10", enabled = free > 0, callback = function() self:increaseWorker(job.name, 10) end },
                }
            end
        end
    end
    return { title = self:locationName(), lines = lines, buttons = buttons }
end

return Outside
