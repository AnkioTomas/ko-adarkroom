-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- Port of A Dark Room script/prestige.js.
--[[--
声望：通关时把部分库存（随机缩减）与总分记进 previous.*，重开后保留；
新世界里出现「被摧毁的村落」（cache）地标，进去可取回这批库存（collectStores）。
--]]
local Prestige = {}

Prestige.storesMap = {
    { store = "wood", type = "g" }, { store = "fur", type = "g" }, { store = "meat", type = "g" },
    { store = "iron", type = "g" }, { store = "coal", type = "g" }, { store = "sulphur", type = "g" },
    { store = "steel", type = "g" }, { store = "cured meat", type = "g" }, { store = "scales", type = "g" },
    { store = "teeth", type = "g" }, { store = "leather", type = "g" }, { store = "bait", type = "g" },
    { store = "torch", type = "g" }, { store = "cloth", type = "g" }, { store = "bone spear", type = "w" },
    { store = "iron sword", type = "w" }, { store = "steel sword", type = "w" }, { store = "bayonet", type = "w" },
    { store = "rifle", type = "w" }, { store = "laser rifle", type = "w" }, { store = "bullets", type = "a" },
    { store = "energy cell", type = "a" }, { store = "grenade", type = "a" }, { store = "bolas", type = "a" },
}

function Prestige.randGen(storeType)
    local amount
    if storeType == "g" then
        amount = math.floor(math.random() * 10)
    elseif storeType == "w" then
        amount = math.floor(math.floor(math.random() * 10) / 2)
    elseif storeType == "a" then
        amount = math.ceil(math.random() * 10 * math.ceil(math.random() * 10))
    else
        return 1
    end
    if amount ~= 0 then return amount end
    return 1
end

--- 按 storesMap 顺序取库存数组；reduce 时每项除以随机数（原版行为）。
function Prestige.getStores(engine, reduce)
    local sm, stores = engine.state, {}
    for i, s in ipairs(Prestige.storesMap) do
        stores[i] = math.floor(sm:get('stores["' .. s.store .. '"]', true) / (reduce and Prestige.randGen(s.type) or 1))
    end
    return stores
end

function Prestige.get(engine)
    local sm = engine.state
    return { stores = sm:get("previous.stores"), score = sm:get("previous.score") }
end

function Prestige.set(engine, prestige)
    local sm = engine.state
    sm:set("previous.stores", prestige.stores)
    sm:set("previous.score", prestige.score)
end

function Prestige.save(engine)
    local sm = engine.state
    sm:set("previous.stores", Prestige.getStores(engine, true))
    sm:set("previous.score", require("adarkroom.score").totalScore(engine))
end

function Prestige.collectStores(engine)
    local sm = engine.state
    local prev = sm:get("previous.stores")
    if type(prev) == "table" and #prev > 0 then
        local toAdd = {}
        for i, s in ipairs(Prestige.storesMap) do toAdd[s.store] = prev[i] or 0 end
        sm:addM("stores", toAdd)
        -- 取回后清空（原版 prevStores.length = 0）
        sm:set("previous.stores", {})
    end
end

return Prestige
