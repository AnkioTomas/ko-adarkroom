-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- Port of A Dark Room script/space.js (ascent and ending), reworked as a turn-based game for e-ink.
--[[--
太空：原版是 60 秒的实时躲陨石（键盘控制，陨石按高度加速加密）。电子墨水屏刷不动动画，
这里改成回合制：每点一次方向按钮算一回合，飞船横移后所有陨石下落，高度 +1，
到 60 以上即通关。陨石数量随高度增加（原版在 10 / 20 / 40 以上各多刷一批），
高处的陨石有概率一回合落两格。引擎（thrusters）越高，一回合能横移的格数越多。
被撞一次船身 -1，船身归零即坠毁，回到星舰（起飞重新冷却）。

通关后照原版：记分（Score.save）、记声望（Prestige.save），删档但保留声望，
有舰队信标时先放「扩展结局」文字；然后显示本局得分 / 总分和「重新开始」。
原版结局里的 iOS / Android 商店链接按纯离线要求去掉了。
--]]
local L = require("adarkroom.l10n")

local Space = {}
Space.__index = Space

Space.WIDTH = 9          -- 列
Space.HEIGHT = 10        -- 行（飞船在最底行）
Space.WIN_ALTITUDE = 60  -- 原版 altitude > 60 时 endGame
Space.ASTEROIDS = { "#", "$", "%", "&", "H" }

function Space.new(engine)
    return setmetatable({ engine = engine, name = "space", hidden = true }, Space)
end

function Space:locationName() return L("Space") end

function Space:getSpeed()
    return 1 + math.floor(self.engine.state:get("game.spaceShip.thrusters", true) / 2)
end

function Space:onArrival()
    local sm = self.engine.state
    self.done, self.ending = false, nil
    self.altitude = 0
    self.hull = sm:get("game.spaceShip.hull", true)
    self.maxHull = self.hull
    self.x = math.ceil(Space.WIDTH / 2)
    self.asteroids = {}
    self.hits = 0
end

function Space:getTitle()
    local a = self.altitude or 0
    if a < 10 then return L("Troposphere")
    elseif a < 20 then return L("Stratosphere")
    elseif a < 30 then return L("Mesosphere")
    elseif a < 45 then return L("Thermosphere")
    elseif a < 60 then return L("Exosphere") end
    return L("Space")
end

--- 原版 createAsteroid 的节奏：基础一批，高度 >10 / >20 / >40 各多一批。
function Space:spawn()
    local n = 1
    if self.altitude > 10 then n = n + 1 end
    if self.altitude > 20 then n = n + 1 end
    if self.altitude > 40 then n = n + 1 end
    local fastChance = math.min(0.5, self.altitude / 100)
    local used = {}
    for _ = 1, n do
        local col = math.random(Space.WIDTH)
        if not used[col] then
            used[col] = true
            self.asteroids[#self.asteroids + 1] = {
                x = col, y = 1, ch = Space.ASTEROIDS[math.random(#Space.ASTEROIDS)],
                speed = math.random() < fastChance and 2 or 1,
            }
        end
    end
end

function Space:hit(a)
    a.dead = true
    self.hull = self.hull - 1
    self.hits = self.hits + 1
end

--- 一回合：dx 为横移格数（负为左）。
function Space:turn(dx)
    if self.done then return end
    self.x = math.max(1, math.min(Space.WIDTH, self.x + dx))
    -- 横移进陨石所在格
    for _, a in ipairs(self.asteroids) do
        if not a.dead and a.y == Space.HEIGHT and a.x == self.x then self:hit(a) end
    end
    -- 陨石下落（掠过飞船所在格也算撞上）
    for _, a in ipairs(self.asteroids) do
        if not a.dead then
            local from = a.y
            a.y = a.y + a.speed
            if a.x == self.x and from < Space.HEIGHT and a.y >= Space.HEIGHT then self:hit(a) end
        end
    end
    local keep = {}
    for _, a in ipairs(self.asteroids) do
        if not a.dead and a.y <= Space.HEIGHT then keep[#keep + 1] = a end
    end
    self.asteroids = keep
    if self.hull <= 0 then return self:crash() end
    self.altitude = self.altitude + 1
    if self.altitude > Space.WIN_ALTITUDE then return self:endGame() end
    self:spawn()
end

function Space:crash()
    if self.done then return end
    self.done = true
    local engine = self.engine
    local ship = engine:module("ship")
    engine:travelTo(ship)
    engine:startCooldown("liftoff", ship.LIFTOFF_COOLDOWN)
end

function Space:endGame()
    if self.done then return end
    self.done = true
    local engine = self.engine
    local Score = require("adarkroom.score")
    local Prestige = require("adarkroom.prestige")
    local beacon = engine.state:get('stores["fleet beacon"]', true) > 0
    Score.save(engine)
    Prestige.save(engine)
    self.ending = {
        score = Score.calculateScore(engine),
        total = Prestige.get(engine).score,
        stage = beacon and "beacon" or "options",
    }
    -- 原版在结局界面出现时 Engine.deleteSave(true)：清档，只留声望
    engine:deleteSave()
    engine:requestRender()
end

function Space:mapLines()
    local grid = {}
    for y = 1, Space.HEIGHT do
        grid[y] = {}
        for x = 1, Space.WIDTH do grid[y][x] = "." end
    end
    for _, a in ipairs(self.asteroids) do grid[a.y][a.x] = a.ch end
    grid[Space.HEIGHT][self.x] = "@"
    local lines = {}
    for y = 1, Space.HEIGHT do lines[y] = table.concat(grid[y], " ") end
    return lines
end

function Space:endingView()
    local e = self.ending
    if e.stage == "beacon" then
        return {
            title = L("Space"),
            lines = {
                L("the beacon pulses gently as the ship glides through space."),
                L("coordinates are locked. nothing to do but wait."),
                "",
                L("the beacon glows a solid blue, and then goes dim. the ship slows."),
                L("gradually, the vast wanderer homefleet comes into view."),
                L("massive worldships drift unnaturally through clouds of debris, scarred and dead."),
                "",
                L("the air is running out."),
                L("the capsule is cold."),
            },
            buttons = { { text = L("wait"), callback = function() e.stage = "options" self.engine:requestRender() end } },
            ending = true,
        }
    end
    return {
        title = L("A Dark Room"),
        lines = { L("score for this game: {0}", e.score), L("total score: {0}", e.total) },
        buttons = { { text = L("restart."), callback = function() self.engine:restart() end } },
        ending = true,
    }
end

function Space:view()
    if self.ending then return self:endingView() end
    local speed = self:getSpeed()
    local lines = {
        L("hull: ") .. self.hull .. "/" .. self.maxHull .. "    " .. self.altitude .. " / " .. Space.WIN_ALTITUDE,
    }
    local row = {}
    if speed > 1 then row[#row + 1] = { text = "⇇", callback = function() self:turn(-speed) self.engine:requestRender() end } end
    row[#row + 1] = { text = "←", callback = function() self:turn(-1) self.engine:requestRender() end }
    row[#row + 1] = { text = "·", callback = function() self:turn(0) self.engine:requestRender() end }
    row[#row + 1] = { text = "→", callback = function() self:turn(1) self.engine:requestRender() end }
    if speed > 1 then row[#row + 1] = { text = "⇉", callback = function() self:turn(speed) self.engine:requestRender() end } end
    return { title = self:getTitle(), lines = lines, map = self:mapLines(), buttons = { row } }
end

return Space
