-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- Port of A Dark Room script/world.js.
--[[--
世界地图。坐标与原版一致：map[x][y]，x、y 取 0..RADIUS*2（Lua 表允许 0 下标），村庄在 (RADIUS, RADIUS)。
curPos = { x, y }（1、2 号元素）。出门时深拷贝 game.world 到 self.state，平安回家才写回；死了就丢弃。
远征进行中的临时状态存进状态树 expedition，关掉插件再打开可以继续（原版刷新网页会丢失）。
--]]
local L = require("adarkroom.l10n")

local World = {}
World.__index = World

World.RADIUS = 30
World.VILLAGE_POS = { 30, 30 }
World.TILE = {
    VILLAGE = "A", IRON_MINE = "I", COAL_MINE = "C", SULPHUR_MINE = "S",
    FOREST = ";", FIELD = ",", BARRENS = ".", ROAD = "#", HOUSE = "H", CAVE = "V",
    TOWN = "O", CITY = "Y", OUTPOST = "P", SHIP = "W", BOREHOLE = "B",
    BATTLEFIELD = "F", SWAMP = "M", CACHE = "U", EXECUTIONER = "X",
}
local TILE = World.TILE
World.TILE_PROBS = { [TILE.FOREST] = 0.15, [TILE.FIELD] = 0.35, [TILE.BARRENS] = 0.5 }
World.TERRAIN_ORDER = { TILE.FOREST, TILE.FIELD, TILE.BARRENS }
World.STICKINESS = 0.5
World.LIGHT_RADIUS = 2
World.BASE_WATER = 10
World.MOVES_PER_FOOD = 2
World.MOVES_PER_WATER = 1
World.DEATH_COOLDOWN = 120
World.FIGHT_CHANCE = 0.20
World.BASE_HEALTH = 10
World.BASE_HIT_CHANCE = 0.8
World.MEAT_HEAL = 8
World.MEDS_HEAL = 20
World.HYPO_HEAL = 30
World.FIGHT_DELAY = 3
World.NORTH = { 0, -1 }
World.SOUTH = { 0, 1 }
World.WEST = { -1, 0 }
World.EAST = { 1, 0 }

World.Weapons = {
    ["fists"] = { verb = L("punch"), type = "unarmed", damage = 1, cooldown = 2 },
    ["bone spear"] = { verb = L("stab"), type = "melee", damage = 2, cooldown = 2 },
    ["iron sword"] = { verb = L("swing"), type = "melee", damage = 4, cooldown = 2 },
    ["steel sword"] = { verb = L("slash"), type = "melee", damage = 6, cooldown = 2 },
    ["bayonet"] = { verb = L("thrust"), type = "melee", damage = 8, cooldown = 2 },
    ["rifle"] = { verb = L("shoot"), type = "ranged", damage = 5, cooldown = 1, cost = { bullets = 1 } },
    ["laser rifle"] = { verb = L("blast"), type = "ranged", damage = 8, cooldown = 1, cost = { ["energy cell"] = 1 } },
    ["grenade"] = { verb = L("lob"), type = "ranged", damage = 15, cooldown = 5, cost = { grenade = 1 } },
    ["bolas"] = { verb = L("tangle"), type = "ranged", damage = "stun", cooldown = 15, cost = { bolas = 1 } },
    ["plasma rifle"] = { verb = L("disintegrate"), type = "ranged", damage = 12, cooldown = 1, cost = { ["energy cell"] = 1 } },
    ["energy blade"] = { verb = L("slice"), type = "melee", damage = 10, cooldown = 2 },
    ["disruptor"] = { verb = L("stun"), type = "ranged", damage = "stun", cooldown = 15 },
}
-- 战斗按钮的稳定顺序（原版按对象定义顺序）
World.WEAPON_ORDER = { "fists", "bone spear", "iron sword", "steel sword", "bayonet", "rifle", "laser rifle",
    "grenade", "bolas", "plasma rifle", "energy blade", "disruptor" }

--- 原版标签用 &nbsp; 连接，翻译表的 key 也带 &nbsp;
local function nb(key) return (L(key):gsub("&nbsp;", " ")) end

-- 地标（原版 World.init）。处决者战舰（Executioner）与制造机属于后续版本内容，见第 5 批。
local function landmarks(sm)
    local R = World.RADIUS
    local lm = {
        { tile = TILE.OUTPOST, num = 0, minRadius = 0, maxRadius = 0, scene = "outpost", label = nb("An&nbsp;Outpost") },
        { tile = TILE.IRON_MINE, num = 1, minRadius = 5, maxRadius = 5, scene = "ironmine", label = nb("Iron&nbsp;Mine") },
        { tile = TILE.COAL_MINE, num = 1, minRadius = 10, maxRadius = 10, scene = "coalmine", label = nb("Coal&nbsp;Mine") },
        { tile = TILE.SULPHUR_MINE, num = 1, minRadius = 20, maxRadius = 20, scene = "sulphurmine", label = nb("Sulphur&nbsp;Mine") },
        { tile = TILE.HOUSE, num = 10, minRadius = 0, maxRadius = R * 1.5, scene = "house", label = nb("An&nbsp;Old&nbsp;House") },
        { tile = TILE.CAVE, num = 5, minRadius = 3, maxRadius = 10, scene = "cave", label = nb("A&nbsp;Damp&nbsp;Cave") },
        { tile = TILE.TOWN, num = 10, minRadius = 10, maxRadius = 20, scene = "town", label = nb("An&nbsp;Abandoned&nbsp;Town") },
        { tile = TILE.CITY, num = 20, minRadius = 20, maxRadius = R * 1.5, scene = "city", label = nb("A&nbsp;Ruined&nbsp;City") },
        { tile = TILE.SHIP, num = 1, minRadius = 28, maxRadius = 28, scene = "ship", label = nb("A&nbsp;Crashed&nbsp;Starship") },
        { tile = TILE.BOREHOLE, num = 10, minRadius = 15, maxRadius = R * 1.5, scene = "borehole", label = nb("A&nbsp;Borehole") },
        { tile = TILE.BATTLEFIELD, num = 5, minRadius = 18, maxRadius = R * 1.5, scene = "battlefield", label = nb("A&nbsp;Battlefield") },
        { tile = TILE.SWAMP, num = 1, minRadius = 15, maxRadius = R * 1.5, scene = "swamp", label = nb("A&nbsp;Murky&nbsp;Swamp") },
    }
    if sm:get("previous.stores") then
        lm[#lm + 1] = { tile = TILE.CACHE, num = 1, minRadius = 10, maxRadius = R * 1.5, scene = "cache", label = nb("A&nbsp;Destroyed&nbsp;Village") }
    end
    return lm
end

local function deepcopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = deepcopy(v) end
    return c
end
World.deepcopy = deepcopy

function World.new(engine)
    local self = setmetatable({ engine = engine, name = "world", hidden = true }, World)
    local sm = engine.state
    self.LANDMARKS = {}
    self.landmarkList = landmarks(sm)
    for _, l in ipairs(self.landmarkList) do self.LANDMARKS[l.tile] = l end
    if type(sm:get("game.world.map")) ~= "table" then
        sm:set("features.location.world", true)
        sm:setM("game.world", { map = self:generateMap(), mask = self:newMask() })
    end
    local ship = self:mapSearch(TILE.SHIP, sm:get("game.world.map"), 1)
    self.dir = ship and ship[1] and World.compassDir(ship[1]) or "north"
    self:testMap()
    return self
end

function World:locationName() return L("A Barren World") end
function World:notify(text) self.engine:notify(self, text) end
function World:outfit() return self.engine.modules.path:outfit() end

-- MAP GENERATION ---------------------------------------------------------------
function World:newGrid()
    local g = {}
    for i = 0, World.RADIUS * 2 do g[i] = {} end
    return g
end

function World:newMask()
    local mask = self:newGrid()
    self:lightMap(World.RADIUS, World.RADIUS, mask)
    return mask
end

function World.isTerrain(tile)
    return tile == TILE.FOREST or tile == TILE.FIELD or tile == TILE.BARRENS
end

function World:chooseTile(x, y, map)
    local R2 = World.RADIUS * 2
    local adjacent = {
        y > 0 and map[x][y - 1] or false,
        y < R2 and map[x][y + 1] or false,
        x < R2 and map[x + 1][y] or false,
        x > 0 and map[x - 1][y] or false,
    }
    local chances, nonSticky = {}, 1
    for i = 1, 4 do
        local a = adjacent[i]
        if a == TILE.VILLAGE then
            return TILE.FOREST -- 村庄必须在森林里
        elseif type(a) == "string" then
            chances[a] = (chances[a] or 0) + World.STICKINESS
            nonSticky = nonSticky - World.STICKINESS
        end
    end
    for _, tile in ipairs(World.TERRAIN_ORDER) do
        chances[tile] = (chances[tile] or 0) + World.TILE_PROBS[tile] * nonSticky
    end
    local list = {}
    for tile, p in pairs(chances) do list[#list + 1] = { p = p, tile = tile } end
    table.sort(list, function(a, b) if a.p ~= b.p then return a.p > b.p end return a.tile < b.tile end)
    local c, r = 0, math.random()
    for _, e in ipairs(list) do
        c = c + e.p
        if r < c then return e.tile end
    end
    return TILE.BARRENS
end

function World:generateMap()
    local R = World.RADIUS
    local map = self:newGrid()
    map[R][R] = TILE.VILLAGE
    for r = 1, R do
        for t = 0, r * 8 - 1 do
            local x, y
            if t < 2 * r then x, y = R - r + t, R - r
            elseif t < 4 * r then x, y = R + r, R - (3 * r) + t
            elseif t < 6 * r then x, y = R + (5 * r) - t, R + r
            else x, y = R - r, R + (7 * r) - t end
            map[x][y] = self:chooseTile(x, y, map)
        end
    end
    for _, l in ipairs(self.landmarkList) do
        for _ = 1, l.num do self:placeLandmark(l.minRadius, l.maxRadius, l.tile, map) end
    end
    return map
end

function World:placeLandmark(minRadius, maxRadius, landmark, map)
    local R = World.RADIUS
    local x, y = R, R
    while not World.isTerrain(map[x][y]) do
        local r = math.floor(math.random() * (maxRadius - minRadius)) + minRadius
        local xDist = math.floor(math.random() * r)
        local yDist = r - xDist
        if math.random() < 0.5 then xDist = -xDist end
        if math.random() < 0.5 then yDist = -yDist end
        x = math.max(0, math.min(R * 2, R + xDist))
        y = math.max(0, math.min(R * 2, R + yDist))
    end
    map[x][y] = landmark
    return { x, y }
end

function World:mapSearch(target, map, required)
    local l = self.LANDMARKS[target]
    local max = l and l.num or 0
    if max == 0 then return nil end
    max = required and math.min(required, max) or max
    local targets = {}
    for i = 0, World.RADIUS * 2 do
        for j = 0, World.RADIUS * 2 do
            local tile = map[i] and map[i][j]
            if type(tile) == "string" and tile:sub(1, 1) == target then
                targets[#targets + 1] = { x = i - World.RADIUS, y = j - World.RADIUS }
                if #targets == max then return targets end
            end
        end
    end
    return targets
end

function World.compassDir(pos)
    local horz = pos.x < 0 and "west" or "east"
    local vert = pos.y < 0 and "north" or "south"
    if math.abs(pos.x) / 2 > math.abs(pos.y) then return horz
    elseif math.abs(pos.y) / 2 > math.abs(pos.x) then return vert end
    return vert .. horz
end

-- FOG ------------------------------------------------------------------------
function World:lightMap(x, y, mask)
    local r = World.LIGHT_RADIUS * (self.engine.state:hasPerk("scout") and 2 or 1)
    self:uncoverMap(x, y, r, mask)
    return mask
end

function World:uncoverMap(x, y, r, mask)
    local R2 = World.RADIUS * 2
    mask[x][y] = true
    for i = -r, r do
        for j = -r + math.abs(i), r - math.abs(i) do
            if y + j >= 0 and y + j <= R2 and x + i <= R2 and x + i >= 0 then
                mask[x + i][y + j] = true
            end
        end
    end
end

function World:testMap()
    if self.seenAll then return end
    local mask = self.engine.state:get("game.world.mask")
    if type(mask) ~= "table" then return end
    for i = 0, World.RADIUS * 2 do
        for j = 0, World.RADIUS * 2 do
            if not (mask[i] and mask[i][j]) then return end
        end
    end
    self.seenAll = true
end

--- 侦察兵卖地图：在存档地图上随机揭开一块（半径 5）。
function World:applyMap()
    if not self.seenAll then
        local mask = self.engine.state:get("game.world.mask")
        local x, y
        repeat
            x = math.floor(math.random() * (World.RADIUS * 2 + 1))
            y = math.floor(math.random() * (World.RADIUS * 2 + 1))
        until not mask[x][y]
        self:uncoverMap(x, y, 5, mask)
        self.engine:requestSave()
    end
    self:testMap()
end

-- DUNGEONS / ROADS -------------------------------------------------------------
function World:clearDungeon()
    self.state.map[self.curPos[1]][self.curPos[2]] = TILE.OUTPOST
    self:drawRoad()
end

function World:drawRoad()
    local R2 = World.RADIUS * 2
    local map = self.state.map
    local function findClosestRoad(start)
        local x, y, dx, dy = 0, 0, 1, -1
        local limit = (self:getDistance(start, World.VILLAGE_POS) + 2) ^ 2
        local i = 0
        while i < limit do
            local sx, sy = start[1] + x, start[2] + y
            if 0 < sx and sx < R2 and 0 < sy and sy < R2 then
                local tile = map[sx][sy]
                if tile == TILE.ROAD or (tile == TILE.OUTPOST and not (x == 0 and y == 0)) or tile == TILE.VILLAGE then
                    return { sx, sy }
                end
            end
            if x == 0 or y == 0 then dx, dy = -dy, dx end
            if x == 0 and y <= 0 then x = x + 1 else x, y = x + dx, y + dy end
            i = i + 1
        end
        return World.VILLAGE_POS
    end
    local cur = self.curPos
    local road = findClosestRoad(cur)
    local xDist, yDist = cur[1] - road[1], cur[2] - road[2]
    local xDir = xDist == 0 and 0 or (xDist > 0 and 1 or -1)
    local yDir = yDist == 0 and 0 or (yDist > 0 and 1 or -1)
    local xI, yI
    if math.abs(xDist) > math.abs(yDist) then
        xI, yI = road[1], road[2] + yDist
    else
        xI, yI = road[1] + xDist, road[2]
    end
    for x = 0, math.abs(xDist) - 1 do
        local px = road[1] + xDir * x
        if World.isTerrain(map[px][yI]) then map[px][yI] = TILE.ROAD end
    end
    for y = 0, math.abs(yDist) - 1 do
        local py = road[2] + yDir * y
        if World.isTerrain(map[xI][py]) then map[xI][py] = TILE.ROAD end
    end
end

function World:markVisited(x, y)
    x, y = x or self.curPos[1], y or self.curPos[2]
    self.state.map[x][y] = self.state.map[x][y] .. "!"
end

-- STATS ----------------------------------------------------------------------
function World:getDistance(from, to)
    from = from or self.curPos
    to = to or World.VILLAGE_POS
    return math.abs(from[1] - to[1]) + math.abs(from[2] - to[2])
end

function World:getTerrain() return self.state.map[self.curPos[1]][self.curPos[2]] end

function World:getMaxHealth()
    local sm = self.engine.state
    if sm:get('stores["kinetic armour"]', true) > 0 then return World.BASE_HEALTH + 75
    elseif sm:get('stores["s armour"]', true) > 0 then return World.BASE_HEALTH + 35
    elseif sm:get('stores["i armour"]', true) > 0 then return World.BASE_HEALTH + 15
    elseif sm:get('stores["l armour"]', true) > 0 then return World.BASE_HEALTH + 5 end
    return World.BASE_HEALTH
end

function World:getHitChance()
    return World.BASE_HIT_CHANCE + (self.engine.state:hasPerk("precise") and 0.1 or 0)
end

function World:getMaxWater()
    local sm = self.engine.state
    if sm:get('stores["fluid recycler"]', true) > 0 then return World.BASE_WATER + 100
    elseif sm:get('stores["water tank"]', true) > 0 then return World.BASE_WATER + 50
    elseif sm:get("stores.cask", true) > 0 then return World.BASE_WATER + 20
    elseif sm:get("stores.waterskin", true) > 0 then return World.BASE_WATER + 10 end
    return World.BASE_WATER
end

function World:meatHeal() return World.MEAT_HEAL * (self.engine.state:hasPerk("gastronome") and 2 or 1) end
function World:medsHeal() return World.MEDS_HEAL end
function World:hypoHeal() return World.HYPO_HEAL end

function World:setWater(w)
    self.water = math.min(w, self:getMaxWater())
end

function World:setHp(hp)
    if type(hp) == "number" and hp == hp then
        self.health = math.min(hp, self:getMaxHealth())
    end
end

function World:outpostUsed(x, y)
    x, y = x or self.curPos[1], y or self.curPos[2]
    return self.usedOutposts[x .. "," .. y] == true
end

function World:useOutpost()
    self.engine:notify(nil, L("water replenished"))
    self:setWater(self:getMaxWater())
    self.usedOutposts[self.curPos[1] .. "," .. self.curPos[2]] = true
end

-- MOVEMENT -------------------------------------------------------------------
function World:moveNorth() if self.curPos[2] > 0 then self:move(World.NORTH) end end
function World:moveSouth() if self.curPos[2] < World.RADIUS * 2 then self:move(World.SOUTH) end end
function World:moveWest() if self.curPos[1] > 0 then self:move(World.WEST) end end
function World:moveEast() if self.curPos[1] < World.RADIUS * 2 then self:move(World.EAST) end end

function World:move(dir)
    local map = self.state.map
    local oldTile = map[self.curPos[1]][self.curPos[2]]
    self.curPos[1] = self.curPos[1] + dir[1]
    self.curPos[2] = self.curPos[2] + dir[2]
    self:narrateMove(oldTile, map[self.curPos[1]][self.curPos[2]])
    self:lightMap(self.curPos[1], self.curPos[2], self.state.mask)
    self:doSpace()
    if self.state and self:checkDanger() then
        if self.danger then
            self:notify(L("dangerous to be this far from the village without proper protection"))
        else
            self:notify(L("safer here"))
        end
    end
    self.engine:requestSave()
    self.engine:requestRender()
end

function World:checkDanger()
    local sm = self.engine.state
    if not self.danger then
        if sm:get('stores["i armour"]', true) == 0 and self:getDistance() >= 8 then
            self.danger = true
            return true
        end
        if sm:get('stores["s armour"]', true) == 0 and self:getDistance() >= 18 then
            self.danger = true
            return true
        end
    else
        if self:getDistance() < 8 then
            self.danger = false
            return true
        end
        -- 原版此处写成 `World.getDistance < 18`（比较函数本身，恒为假），保留原行为
    end
    return false
end

local NARRATE = {
    [TILE.FOREST] = {
        [TILE.FIELD] = "the trees yield to dry grass. the yellowed brush rustles in the wind.",
        [TILE.BARRENS] = "the trees are gone. parched earth and blowing dust are poor replacements.",
    },
    [TILE.FIELD] = {
        [TILE.FOREST] = "trees loom on the horizon. grasses gradually yield to a forest floor of dry branches and fallen leaves.",
        [TILE.BARRENS] = "the grasses thin. soon, only dust remains.",
    },
    [TILE.BARRENS] = {
        [TILE.FIELD] = "the barrens break at a sea of dying grass, swaying in the arid breeze.",
        [TILE.FOREST] = "a wall of gnarled trees rises from the dust. their branches twist into a skeletal canopy overhead.",
    },
}

function World:narrateMove(oldTile, newTile)
    local msg = NARRATE[oldTile] and NARRATE[oldTile][newTile]
    if msg then self:notify(L(msg)) end
end

function World:useSupplies()
    local sm = self.engine.state
    local outfit = self:outfit()
    self.foodMove = self.foodMove + 1
    self.waterMove = self.waterMove + 1
    local movesPerFood = World.MOVES_PER_FOOD * (sm:hasPerk("slow metabolism") and 2 or 1)
    if self.foodMove >= movesPerFood then
        self.foodMove = 0
        local num = (outfit["cured meat"] or 0) - 1
        if num == 0 then
            self:notify(L("the meat has run out"))
        elseif num < 0 then
            num = 0
            if not self.starvation then
                self:notify(L("starvation sets in"))
                self.starvation = true
            else
                sm:add("character.starved", 1)
                if sm:get("character.starved", true) >= 10 and not sm:hasPerk("slow metabolism") then
                    sm:addPerk("slow metabolism")
                end
                self:die()
                return false
            end
        else
            self.starvation = false
            self:setHp(self.health + self:meatHeal())
        end
        outfit["cured meat"] = num
    end
    local movesPerWater = World.MOVES_PER_WATER * (sm:hasPerk("desert rat") and 2 or 1)
    if self.waterMove >= movesPerWater then
        self.waterMove = 0
        local water = self.water - 1
        if water == 0 then
            self:notify(L("there is no more water"))
        elseif water < 0 then
            water = 0
            if not self.thirst then
                self:notify(L("the thirst becomes unbearable"))
                self.thirst = true
            else
                sm:add("character.dehydrated", 1)
                if sm:get("character.dehydrated", true) >= 10 and not sm:hasPerk("desert rat") then
                    sm:addPerk("desert rat")
                end
                self:die()
                return false
            end
        else
            self.thirst = false
        end
        self:setWater(water)
    end
    return true
end

function World:checkFight()
    self.fightMove = (self.fightMove or 0) + 1
    if self.fightMove > World.FIGHT_DELAY then
        local chance = World.FIGHT_CHANCE * (self.engine.state:hasPerk("stealthy") and 0.5 or 1)
        if math.random() < chance then
            self.fightMove = 0
            self.engine.events:triggerFight()
        end
    end
end

function World:doSpace()
    local tile = self:getTerrain()
    if tile == TILE.VILLAGE then
        self:goHome()
    elseif self.LANDMARKS[tile] then
        if tile ~= TILE.OUTPOST or not self:outpostUsed() then
            self.engine.events:startEvent(self.engine.events:setpiece(self.LANDMARKS[tile].scene))
        end
    else
        if self:useSupplies() then self:checkFight() end
    end
end

-- ARRIVAL / DEATH / HOME -----------------------------------------------------------
function World:onArrival()
    self.state = deepcopy(self.engine.state:get("game.world"))
    self:setWater(self:getMaxWater())
    self:setHp(self:getMaxHealth())
    self.foodMove, self.waterMove = 0, 0
    self.starvation, self.thirst = false, false
    self.usedOutposts = {}
    self.curPos = { World.VILLAGE_POS[1], World.VILLAGE_POS[2] }
    self.dead = false
    self.danger = false
end

--- 远征快照（存档用）；不在远征中返回 nil。
function World:snapshot()
    if not self.state then return nil end
    return {
        state = self.state, curPos = self.curPos, water = self.water, health = self.health,
        foodMove = self.foodMove, waterMove = self.waterMove, starvation = self.starvation,
        thirst = self.thirst, usedOutposts = self.usedOutposts, danger = self.danger, fightMove = self.fightMove,
    }
end

function World:resume(snap)
    for k, v in pairs(snap) do self[k] = v end
    self.dead = false
end

function World:die()
    if self.dead then return end
    self.dead = true
    local engine = self.engine
    engine.events:abortCombat()
    self:notify(L("the world fades"))
    self.state = nil
    engine.state:remove("outfit")
    engine.state:remove("expedition", true)
    engine:setTimeout(function()
        engine:travelTo(engine.modules.room)
        engine:startCooldown("embark", World.DEATH_COOLDOWN)
    end, 2)
    engine:requestRender()
end

function World:goHome()
    local engine, sm = self.engine, self.engine.state
    sm:setM("game.world", self.state)
    self:testMap()
    if self.state.sulphurmine and sm:get('game.buildings["sulphur mine"]', true) == 0 then
        sm:add('game.buildings["sulphur mine"]', 1)
    end
    if self.state.ironmine and sm:get('game.buildings["iron mine"]', true) == 0 then
        sm:add('game.buildings["iron mine"]', 1)
    end
    if self.state.coalmine and sm:get('game.buildings["coal mine"]', true) == 0 then
        sm:add('game.buildings["coal mine"]', 1)
    end
    if self.state.ship and not sm:get("features.location.spaceShip") then
        -- 飞船模块在第 5 批；先记下发现，届时由 ship 模块接管
        local ok = pcall(require, "adarkroom.ship")
        if ok then engine:module("ship") else sm:set("game.foundShip", true) end
    end
    self.state = nil
    self:returnOutfit()
    sm:remove("expedition", true)
    engine:travelTo(engine.modules.path)
end

function World:returnOutfit()
    local sm = self.engine.state
    local outfit = self:outfit()
    for k, n in pairs(outfit) do
        sm:add('stores["' .. k .. '"]', n)
        if self:leaveItAtHome(k) then outfit[k] = 0 end
    end
    sm:set("outfit", outfit)
end

function World:leaveItAtHome(thing)
    local Items = require("adarkroom.items")
    local item = Items.byName[thing]
    return thing ~= "cured meat" and thing ~= "bullets" and thing ~= "energy cell" and thing ~= "charm"
        and thing ~= "medicine" and thing ~= "stim" and thing ~= "hypo"
        and World.Weapons[thing] == nil and not (item and Items.isCraftable(thing))
end

-- VIEW -----------------------------------------------------------------------
World.VIEW_W = 21 -- 视窗宽（列）
World.VIEW_H = 15 -- 视窗高（行）

--- 以玩家为中心的地图视窗，等宽 ASCII；未探索处为空格。
function World:mapLines(w, h)
    w, h = w or World.VIEW_W, h or World.VIEW_H
    local R2 = World.RADIUS * 2
    local x0 = math.max(0, math.min(R2 - w + 1, self.curPos[1] - math.floor(w / 2)))
    local y0 = math.max(0, math.min(R2 - h + 1, self.curPos[2] - math.floor(h / 2)))
    local lines = {}
    for j = y0, y0 + h - 1 do
        local row = {}
        for i = x0, x0 + w - 1 do
            local c
            if i == self.curPos[1] and j == self.curPos[2] then
                c = "@"
            elseif self.state.mask[i][j] then
                c = self.state.map[i][j]
                if self.LANDMARKS[c] and c == TILE.OUTPOST and self:outpostUsed(i, j) then c = TILE.OUTPOST end
                c = c:sub(1, 1)
            else
                c = " "
            end
            row[#row + 1] = c
        end
        lines[#lines + 1] = table.concat(row)
    end
    return lines
end

function World:view()
    local engine = self.engine
    if not self.state then return { title = self:locationName(), lines = { L("the world fades") }, buttons = {} } end
    local outfit = self:outfit()
    local lines = {
        L("hp: {0}/{1}", self.health, self:getMaxHealth()) .. "   " .. L("water:{0}", self.water),
    }
    local supplies = {}
    for k, n in pairs(outfit) do if n > 0 then supplies[#supplies + 1] = L(k) .. ":" .. n end end
    table.sort(supplies)
    if #supplies > 0 then lines[#lines + 1] = table.concat(supplies, "  ") end
    local path = engine.modules.path
    lines[#lines + 1] = L("free {0}/{1}", math.floor(path:getFreeSpace()), path:getCapacity())
    local here = self:getTerrain():sub(1, 1)
    local lm = self.LANDMARKS[here]
    if lm then lines[#lines + 1] = "@ " .. lm.label end
    local function mv(text, fn) return { text = text, callback = function() fn(self) end } end
    return {
        title = self:locationName(),
        map = self:mapLines(),
        lines = lines,
        buttons = {
            { mv("北", World.moveNorth) },
            { mv("西", World.moveWest), mv("东", World.moveEast) },
            { mv("南", World.moveSouth) },
        },
    }
end

return World
