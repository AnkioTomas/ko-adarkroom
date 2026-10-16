-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- Port of A Dark Room script/ship.js.
--[[--
破旧星舰：用外星合金加固船身、升级引擎，然后起飞进入太空（space.lua）。
--]]
local L = require("adarkroom.l10n")

local Ship = {}
Ship.__index = Ship

Ship.LIFTOFF_COOLDOWN = 120
Ship.ALLOY_PER_HULL = 1
Ship.ALLOY_PER_THRUSTER = 1
Ship.BASE_HULL = 0
Ship.BASE_THRUSTERS = 1

function Ship.new(engine)
    local self = setmetatable({ engine = engine, name = "ship" }, Ship)
    local sm = engine.state
    if not sm:get("features.location.spaceShip") then
        sm:set("features.location.spaceShip", true, true)
        sm:setM("game.spaceShip", { hull = Ship.BASE_HULL, thrusters = Ship.BASE_THRUSTERS }, true)
    end
    sm:remove("game.foundShip", true) -- 第 4 批的占位标记
    return self
end

function Ship:locationName() return L("An Old Starship") end

function Ship:onArrival()
    local sm = self.engine.state
    if not sm:get("game.spaceShip.seenShip") then
        self.engine:notify(self, L("somewhere above the debris cloud, the wanderer fleet hovers. been on this rock too long."))
        sm:set("game.spaceShip.seenShip", true)
    end
end

--- 原版 Ship.getMaxHull（计分也用）；没有飞船时为 0。
function Ship.getMaxHull(engine)
    return engine.state:get("game.spaceShip.hull", true)
end

function Ship:reinforceHull()
    local sm = self.engine.state
    if sm:get('stores["alien alloy"]', true) < Ship.ALLOY_PER_HULL then
        self.engine:notify(self, L("not enough alien alloy"))
        return false
    end
    sm:add('stores["alien alloy"]', -Ship.ALLOY_PER_HULL)
    sm:add("game.spaceShip.hull", 1)
end

function Ship:upgradeEngine()
    local sm = self.engine.state
    if sm:get('stores["alien alloy"]', true) < Ship.ALLOY_PER_THRUSTER then
        self.engine:notify(self, L("not enough alien alloy"))
        return false
    end
    sm:add('stores["alien alloy"]', -Ship.ALLOY_PER_THRUSTER)
    sm:add("game.spaceShip.thrusters", 1)
end

function Ship:checkLiftOff()
    local engine, sm = self.engine, self.engine.state
    if not sm:get("game.spaceShip.seenWarning") then
        engine.events:startEvent{
            title = L("Ready to Leave?"),
            scenes = {
                start = {
                    text = { L("time to get out of this place. won't be coming back.") },
                    buttons = {
                        { id = "fly", text = L("lift off"), nextScene = "end", onChoose = function()
                            sm:set("game.spaceShip.seenWarning", true)
                            -- 先关掉这个事件再起飞（原版 onChoose 先于 endEvent，但界面上没区别）
                            engine:setTimeout(function() self:liftOff() end, 0)
                        end },
                        { id = "wait", text = L("linger"), nextScene = "end", onChoose = function()
                            engine:clearCooldown("liftoff")
                        end },
                    },
                },
            },
        }
    else
        self:liftOff()
    end
end

function Ship:liftOff()
    local engine = self.engine
    local space = engine:module("space")
    engine:travelTo(space)
end

function Ship:view()
    local engine, sm = self.engine, self.engine.state
    local lines = {
        L("hull:") .. " " .. sm:get("game.spaceShip.hull", true),
        L("engine:") .. " " .. sm:get("game.spaceShip.thrusters", true),
        "",
    }
    for _, l in ipairs(engine.modules.room:storesLines()) do lines[#lines + 1] = l end
    local buttons = {
        engine:button{ text = L("reinforce hull"), cost = { ["alien alloy"] = Ship.ALLOY_PER_HULL },
            callback = function() return self:reinforceHull() end },
        engine:button{ text = L("upgrade engine"), cost = { ["alien alloy"] = Ship.ALLOY_PER_THRUSTER },
            callback = function() return self:upgradeEngine() end },
        engine:button{ id = "liftoff", text = L("lift off"), cooldown = Ship.LIFTOFF_COOLDOWN,
            enabled = sm:get("game.spaceShip.hull", true) > 0,
            callback = function() self:checkLiftOff() end },
    }
    return { title = self:locationName(), lines = lines, buttons = buttons }
end

return Ship
