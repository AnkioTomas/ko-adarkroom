-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- Port of A Dark Room script/events/outside.js.
local L = require("adarkroom.l10n")

local function outside(engine) return engine.activeModule ~= nil and engine.activeModule.name == "outside" end
local function home(notification)
    return { { id = "end", text = L("go home"), notification = notification, nextScene = "end" } }
end
local function kill(engine, n) engine.modules.outside:killVillagers(n) end
local function pop(engine) return engine.state:get("game.population", true) end

return {
    { -- Ruined traps
        title = L("A Ruined Trap"),
        isAvailable = function(engine) return outside(engine) and engine.state:get('game.buildings["trap"]', true) > 0 end,
        scenes = {
            start = {
                text = { L("some of the traps have been torn apart."), L("large prints lead away, into the forest.") },
                onLoad = function(engine)
                    local sm = engine.state
                    local n = math.floor(math.random() * sm:get('game.buildings["trap"]', true)) + 1
                    sm:add('game.buildings["trap"]', -n)
                end,
                notification = L("some traps have been destroyed"),
                blink = true,
                buttons = {
                    { id = "track", text = L("track them"), nextScene = { [0.5] = "nothing", [1] = "catch" } },
                    { id = "ignore", text = L("ignore them"), nextScene = "end" },
                },
            },
            nothing = { text = { L("the tracks disappear after just a few minutes."), L("the forest is silent.") },
                notification = L("nothing was found"), buttons = home() },
            catch = { text = { L("not far from the village lies a large beast, its fur matted with blood."),
                    L("it puts up little resistance before the knife.") },
                notification = L("there was a beast. it's dead now"),
                reward = { fur = 100, meat = 100, teeth = 10 }, buttons = home() },
        },
    },
    { -- Hut fire
        title = L("Fire"),
        isAvailable = function(engine)
            return outside(engine) and engine.state:get('game.buildings["hut"]', true) > 0 and pop(engine) > 50
        end,
        scenes = {
            start = {
                text = { L("a fire rampages through one of the huts, destroying it."), L("all residents in the hut perished in the fire.") },
                notification = L("a fire has started"),
                blink = true,
                onLoad = function(engine) engine.modules.outside:destroyHuts(1) end,
                buttons = { { id = "mourn", text = L("mourn"), notification = L("some villagers have died"), nextScene = "end" } },
            },
        },
    },
    { -- Sickness
        title = L("Sickness"),
        isAvailable = function(engine)
            return outside(engine) and pop(engine) > 10 and pop(engine) < 50 and engine.state:get("stores.medicine", true) > 0
        end,
        scenes = {
            start = {
                text = { L("a sickness is spreading through the village."), L("medicine is needed immediately.") },
                notification = L("some villagers are ill"),
                blink = true,
                buttons = {
                    { id = "heal", text = L("1 medicine"), cost = { medicine = 1 }, nextScene = { [1] = "healed" } },
                    { id = "ignore", text = L("ignore it"), nextScene = { [1] = "death" } },
                },
            },
            healed = { text = { L("the sickness is cured in time.") }, notification = L("sufferers are healed"), buttons = home() },
            death = {
                text = { L("the sickness spreads through the village."), L("the days are spent with burials."), L("the nights are rent with screams.") },
                notification = L("sufferers are left to die"),
                onLoad = function(engine) kill(engine, math.floor(math.random() * math.floor(pop(engine) / 2)) + 1) end,
                buttons = home(),
            },
        },
    },
    { -- Plague
        title = L("Plague"),
        isAvailable = function(engine)
            return outside(engine) and pop(engine) > 50 and engine.state:get("stores.medicine", true) > 0
        end,
        scenes = {
            start = {
                text = { L("a terrible plague is fast spreading through the village."), L("medicine is needed immediately.") },
                notification = L("a plague afflicts the village"),
                blink = true,
                buttons = {
                    -- 急需药品，所以涨价
                    { id = "buyMedicine", text = L("buy medicine"), cost = { scales = 70, teeth = 50 }, reward = { medicine = 1 } },
                    { id = "heal", text = L("5 medicine"), cost = { medicine = 5 }, nextScene = { [1] = "healed" } },
                    { id = "ignore", text = L("do nothing"), nextScene = { [1] = "death" } },
                },
            },
            healed = {
                text = { L("the plague is kept from spreading."), L("only a few die."), L("the rest bury them.") },
                notification = L("epidemic is eradicated eventually"),
                onLoad = function(engine) kill(engine, math.floor(math.random() * 5) + 2) end,
                buttons = home(),
            },
            death = {
                text = { L("the plague rips through the village."), L("the nights are rent with screams."), L("the only hope is a quick death.") },
                notification = L("population is almost exterminated"),
                onLoad = function(engine) kill(engine, math.floor(math.random() * 80) + 10) end,
                buttons = home(),
            },
        },
    },
    { -- Beast attack
        title = L("A Beast Attack"),
        isAvailable = function(engine) return outside(engine) and pop(engine) > 0 end,
        scenes = {
            start = {
                text = { L("a pack of snarling beasts pours out of the trees."),
                    L("the fight is short and bloody, but the beasts are repelled."),
                    L("the villagers retreat to mourn the dead.") },
                notification = L("wild beasts attack the villagers"),
                onLoad = function(engine) kill(engine, math.floor(math.random() * 10) + 1) end,
                reward = { fur = 100, meat = 100, teeth = 10 },
                blink = true,
                buttons = home(L("predators become prey. price is unfair")),
            },
        },
    },
    { -- Soldier attack
        title = L("A Military Raid"),
        isAvailable = function(engine)
            return outside(engine) and pop(engine) > 0 and engine.state:get("game.cityCleared")
        end,
        scenes = {
            start = {
                text = { L("a gunshot rings through the trees."),
                    L("well armed men charge out of the forest, firing into the crowd."),
                    L("after a skirmish they are driven away, but not without losses.") },
                notification = L("troops storm the village"),
                onLoad = function(engine) kill(engine, math.floor(math.random() * 40) + 1) end,
                reward = { bullets = 10, ["cured meat"] = 50 },
                blink = true,
                buttons = home(L("warfare is bloodthirsty")),
            },
        },
    },
}
