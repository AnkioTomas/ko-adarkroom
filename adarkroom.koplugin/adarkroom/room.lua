-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- Port of A Dark Room script/room.js (fire & temperature only; builder/crafting in batch 3).
local L = require("adarkroom.l10n")

local Room = {}
Room.__index = Room

Room.FIRE_COOL_DELAY = 5 * 60 -- 秒
Room.ROOM_WARM_DELAY = 30
Room.TEMP = { "freezing", "cold", "mild", "warm", "hot" }      -- value 0..4
Room.FIRE = { "dead", "smoldering", "flickering", "burning", "roaring" }

function Room.new(engine)
    local self = setmetatable({ engine = engine, name = "room" }, Room)
    local sm = engine.state
    if sm:get("game.temperature.value") == nil then sm:set("game.temperature", { value = 0 }, true) end
    if sm:get("game.fire.value") == nil then sm:set("game.fire", { value = 0 }, true) end
    if sm:get("game.builder.level") == nil then sm:set("game.builder.level", -1, true) end
    sm:set("features.location.room", true, true)
    self.fireTimer = engine:setTimeout(function() self:coolFire() end, Room.FIRE_COOL_DELAY)
    self.tempTimer = engine:setTimeout(function() self:adjustTemp() end, Room.ROOM_WARM_DELAY)
    return self
end

function Room:fire() return self.engine.state:get("game.fire.value") or 0 end
function Room:temp() return self.engine.state:get("game.temperature.value") or 0 end

function Room:onArrival()
    self.engine:notify(self, L("the room is {0}", L(Room.TEMP[self:temp() + 1])))
    self.engine:notify(self, L("the fire is {0}", L(Room.FIRE[self:fire() + 1])))
end

function Room:lightFire()
    local sm = self.engine.state
    local wood = sm:get("stores.wood")
    if type(wood) == "number" and wood < 5 then
        self.engine:notify(self, L("not enough wood to get the fire going"))
        return
    elseif type(wood) == "number" then
        sm:set("stores.wood", wood - 5)
    end
    sm:set("game.fire", { value = 3 })
    self:onFireChange()
end

function Room:stokeFire()
    local sm = self.engine.state
    local wood = sm:get("stores.wood")
    if wood == 0 then
        self.engine:notify(self, L("the wood has run out"))
        return
    end
    if type(wood) == "number" then sm:set("stores.wood", wood - 1) end
    if self:fire() < 4 then sm:set("game.fire", { value = self:fire() + 1 }) end
    self:onFireChange()
end

function Room:onFireChange()
    local sm = self.engine.state
    self.engine:notify(self, L("the fire is {0}", L(Room.FIRE[self:fire() + 1])), true)
    if self:fire() > 1 and (sm:get("game.builder.level") or -1) < 0 then
        sm:set("game.builder.level", 0)
        self.engine:notify(self, L("the light from the fire spills from the windows, out into the dark"))
        -- 建造者到来（updateBuilderState）在第 3 批
    end
    self.engine:clearTimeout(self.fireTimer)
    self.fireTimer = self.engine:setTimeout(function() self:coolFire() end, Room.FIRE_COOL_DELAY)
    self.engine:requestRender()
end

function Room:coolFire()
    local sm = self.engine.state
    local wood = sm:get("stores.wood")
    if self:fire() <= 2 and (sm:get("game.builder.level") or -1) > 3 and type(wood) == "number" and wood > 0 then
        self.engine:notify(self, L("builder stokes the fire"), true)
        sm:set("stores.wood", wood - 1)
        sm:set("game.fire", { value = self:fire() + 1 })
    end
    if self:fire() > 0 then
        sm:set("game.fire", { value = self:fire() - 1 })
        self:onFireChange()
    end
end

function Room:adjustTemp()
    local sm = self.engine.state
    local t, f = self:temp(), self:fire()
    if t > 0 and t > f then
        sm:set("game.temperature", { value = t - 1 })
        self.engine:notify(self, L("the room is {0}", L(Room.TEMP[t])), true)
    elseif t < 4 and t < f then
        sm:set("game.temperature", { value = t + 1 })
        self.engine:notify(self, L("the room is {0}", L(Room.TEMP[t + 2])), true)
    end
    self.tempTimer = self.engine:setTimeout(function() self:adjustTemp() end, Room.ROOM_WARM_DELAY)
end

function Room:view()
    local sm = self.engine.state
    local title = self:fire() < 2 and L("A Dark Room") or L("A Firelit Room")
    local lines = {}
    local stores = sm:get("stores") or {}
    local keys = {}
    for k, v in pairs(stores) do if type(v) == "number" then keys[#keys + 1] = k end end
    table.sort(keys)
    for _, k in ipairs(keys) do lines[#lines + 1] = L(k) .. "：" .. math.floor(stores[k]) end
    local buttons = {}
    if self:fire() == 0 then
        buttons[1] = { text = L("light fire"), callback = function() self:lightFire() end }
    else
        buttons[1] = { text = L("stoke fire"), callback = function() self:stokeFire() end }
    end
    return { title = title, lines = lines, buttons = buttons }
end

return Room
