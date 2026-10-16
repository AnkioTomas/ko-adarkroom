-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- Port of A Dark Room script/events/room.js.
local Events = require("adarkroom.events")
local L = require("adarkroom.l10n")

local function inRoom(engine) return engine.activeModule ~= nil and engine.activeModule.name == "room" end
local function bye(text, id) return { { id = id or "leave", text = text or L("say goodbye"), nextScene = "end" } } end

--- 被拿走一成木头、换来少量 store（Noises Inside 的三个分支）
local function woodFor(store)
    return function(engine)
        local sm = engine.state
        local numWood = math.floor(sm:get("stores.wood", true) * 0.1)
        if numWood == 0 then numWood = 1 end
        local n = math.floor(numWood / 5)
        if n == 0 then n = 1 end
        sm:addM("stores", { wood = -numWood, [store] = n })
    end
end

--- 神秘流浪者：概率登记延迟回报（原版 Events.saveDelay，60 秒后回来）
local function wanderer(action, store, amount, chance, text)
    Events.delayed[action] = function(engine)
        engine.state:add("stores." .. store, amount)
        engine:notify(engine.modules.room, text)
    end
    return function(engine)
        if math.random() < chance then engine.events:saveDelay(action, 60) end
    end
end

local function perkButton(id, text, perk)
    return { id = id, text = text, nextScene = "end",
        available = function(engine) return not engine.state:hasPerk(perk) end,
        onChoose = function(engine) engine.state:addPerk(perk) end }
end

return {
    { -- The Nomad -- Merchant
        title = L("The Nomad"),
        isAvailable = function(engine) return inRoom(engine) and engine.state:get("stores.fur", true) > 0 end,
        scenes = {
            start = {
                text = {
                    L("a nomad shuffles into view, laden with makeshift bags bound with rough twine."),
                    L("won't say from where he came, but it's clear that he's not staying."),
                },
                notification = L("a nomad arrives, looking to trade"),
                blink = true,
                buttons = {
                    { id = "buyScales", text = L("buy scales"), cost = { fur = 100 }, reward = { scales = 1 } },
                    { id = "buyTeeth", text = L("buy teeth"), cost = { fur = 200 }, reward = { teeth = 1 } },
                    { id = "buyBait", text = L("buy bait"), cost = { fur = 5 }, reward = { bait = 1 },
                      notification = L("traps are more effective with bait.") },
                    { id = "buyCompass", text = L("buy compass"), cost = { fur = 300, scales = 15, teeth = 5 },
                      reward = { compass = 1 },
                      available = function(engine) return engine.state:get("stores.compass", true) < 1 end,
                      notification = L("the old compass is dented and dusty, but it looks to work.") },
                    { id = "goodbye", text = L("say goodbye"), nextScene = "end" },
                },
            },
        },
    },
    { -- Noises Outside -- gain wood/fur
        title = L("Noises"),
        isAvailable = function(engine) return inRoom(engine) and engine.state:get("stores.wood") end,
        scenes = {
            start = {
                text = { L("through the walls, shuffling noises can be heard."), L("can't tell what they're up to.") },
                notification = L("strange noises can be heard through the walls"),
                blink = true,
                buttons = {
                    { id = "investigate", text = L("investigate"), nextScene = { [0.3] = "stuff", [1] = "nothing" } },
                    { id = "ignore", text = L("ignore them"), nextScene = "end" },
                },
            },
            nothing = { text = { L("vague shapes move, just out of sight."), L("the sounds stop.") },
                buttons = bye(L("go back inside"), "backinside") },
            stuff = { reward = { wood = 100, fur = 10 },
                text = { L("a bundle of sticks lies just beyond the threshold, wrapped in coarse furs."), L("the night is silent.") },
                buttons = bye(L("go back inside"), "backinside") },
        },
    },
    { -- Noises Inside -- trade wood for better good
        title = L("Noises"),
        isAvailable = function(engine) return inRoom(engine) and engine.state:get("stores.wood") end,
        scenes = {
            start = {
                text = { L("scratching noises can be heard from the store room."), L("something's in there.") },
                notification = L("something's in the store room"),
                blink = true,
                buttons = {
                    { id = "investigate", text = L("investigate"), nextScene = { [0.5] = "scales", [0.8] = "teeth", [1] = "cloth" } },
                    { id = "ignore", text = L("ignore them"), nextScene = "end" },
                },
            },
            scales = { text = { L("some wood is missing."), L("the ground is littered with small scales") },
                onLoad = woodFor("scales"), buttons = bye(L("leave")) },
            teeth = { text = { L("some wood is missing."), L("the ground is littered with small teeth") },
                onLoad = woodFor("teeth"), buttons = bye(L("leave")) },
            cloth = { text = { L("some wood is missing."), L("the ground is littered with scraps of cloth") },
                onLoad = woodFor("cloth"), buttons = bye(L("leave")) },
        },
    },
    { -- The Beggar -- trade fur for better good
        title = L("The Beggar"),
        isAvailable = function(engine) return inRoom(engine) and engine.state:get("stores.fur") end,
        scenes = {
            start = {
                text = { L("a beggar arrives."), L("asks for any spare furs to keep him warm at night.") },
                notification = L("a beggar arrives"),
                blink = true,
                buttons = {
                    { id = "50furs", text = L("give 50"), cost = { fur = 50 }, nextScene = { [0.5] = "scales", [0.8] = "teeth", [1] = "cloth" } },
                    { id = "100furs", text = L("give 100"), cost = { fur = 100 }, nextScene = { [0.5] = "teeth", [0.8] = "scales", [1] = "cloth" } },
                    { id = "deny", text = L("turn him away"), nextScene = "end" },
                },
            },
            scales = { reward = { scales = 20 }, text = { L("the beggar expresses his thanks."), L("leaves a pile of small scales behind.") }, buttons = bye() },
            teeth = { reward = { teeth = 20 }, text = { L("the beggar expresses his thanks."), L("leaves a pile of small teeth behind.") }, buttons = bye() },
            cloth = { reward = { cloth = 20 }, text = { L("the beggar expresses his thanks."), L("leaves some scraps of cloth behind.") }, buttons = bye() },
        },
    },
    { -- The Shady Builder
        title = L("The Shady Builder"),
        isAvailable = function(engine)
            local huts = engine.state:get('game.buildings["hut"]', true)
            return inRoom(engine) and huts >= 5 and huts < 20
        end,
        scenes = {
            start = {
                text = { L("a shady builder passes through"), L("says he can build you a hut for less wood") },
                notification = L("a shady builder passes through"),
                buttons = {
                    { id = "build", text = L("300 wood"), cost = { wood = 300 }, nextScene = { [0.6] = "steal", [1] = "build" } },
                    { id = "deny", text = L("say goodbye"), nextScene = "end" },
                },
            },
            steal = { text = { L("the shady builder has made off with your wood") },
                notification = L("the shady builder has made off with your wood"), buttons = bye(L("go home"), "end") },
            build = { text = { L("the shady builder builds a hut") }, notification = L("the shady builder builds a hut"),
                onLoad = function(engine)
                    local n = engine.state:get('game.buildings["hut"]', true)
                    if n < 20 then engine.state:set('game.buildings["hut"]', n + 1) end
                end,
                buttons = bye(L("go home"), "end") },
        },
    },
    { -- Mysterious Wanderer -- wood gambling
        title = L("The Mysterious Wanderer"),
        isAvailable = function(engine) return inRoom(engine) and engine.state:get("stores.wood") end,
        scenes = {
            start = {
                text = { L("a wanderer arrives with an empty cart. says if he leaves with wood, he'll be back with more."),
                    L("builder's not sure he's to be trusted.") },
                notification = L("a mysterious wanderer arrives"),
                blink = true,
                buttons = {
                    { id = "wood100", text = L("give 100"), cost = { wood = 100 }, nextScene = { [1] = "wood100" } },
                    { id = "wood500", text = L("give 500"), cost = { wood = 500 }, nextScene = { [1] = "wood500" } },
                    { id = "deny", text = L("turn him away"), nextScene = "end" },
                },
            },
            wood100 = { text = { L("the wanderer leaves, cart loaded with wood") }, buttons = bye(),
                onLoad = wanderer("Room[4].scenes.wood100.action", "wood", 300, 0.5,
                    L("the mysterious wanderer returns, cart piled high with wood.")) },
            wood500 = { text = { L("the wanderer leaves, cart loaded with wood") }, buttons = bye(),
                onLoad = wanderer("Room[4].scenes.wood500.action", "wood", 1500, 0.3,
                    L("the mysterious wanderer returns, cart piled high with wood.")) },
        },
    },
    { -- Mysterious Wanderer -- fur gambling
        title = L("The Mysterious Wanderer"),
        isAvailable = function(engine) return inRoom(engine) and engine.state:get("stores.fur") end,
        scenes = {
            start = {
                text = { L("a wanderer arrives with an empty cart. says if she leaves with furs, she'll be back with more."),
                    L("builder's not sure she's to be trusted.") },
                notification = L("a mysterious wanderer arrives"),
                blink = true,
                buttons = {
                    { id = "fur100", text = L("give 100"), cost = { fur = 100 }, nextScene = { [1] = "fur100" } },
                    { id = "fur500", text = L("give 500"), cost = { fur = 500 }, nextScene = { [1] = "fur500" } },
                    { id = "deny", text = L("turn her away"), nextScene = "end" },
                },
            },
            fur100 = { text = { L("the wanderer leaves, cart loaded with furs") }, buttons = bye(),
                onLoad = wanderer("Room[5].scenes.fur100.action", "fur", 300, 0.5,
                    L("the mysterious wanderer returns, cart piled high with furs.")) },
            fur500 = { text = { L("the wanderer leaves, cart loaded with furs") }, buttons = bye(),
                onLoad = wanderer("Room[5].scenes.fur500.action", "fur", 1500, 0.3,
                    L("the mysterious wanderer returns, cart piled high with furs.")) },
        },
    },
    { -- The Scout -- Map Merchant
        title = L("The Scout"),
        isAvailable = function(engine) return inRoom(engine) and engine.state:get("features.location.world") end,
        scenes = {
            start = {
                text = { L("the scout says she's been all over."), L("willing to talk about it, for a price.") },
                notification = L("a scout stops for the night"),
                blink = true,
                buttons = {
                    { id = "buyMap", text = L("buy map"), cost = { fur = 200, scales = 10 },
                      available = function(engine) local w = engine.modules.world return not (w and w.seenAll) end,
                      notification = L("the map uncovers a bit of the world"),
                      onChoose = function(engine) local w = engine.modules.world if w and w.applyMap then w:applyMap() end end },
                    { id = "learn", text = L("learn scouting"), cost = { fur = 1000, scales = 50, teeth = 20 },
                      available = function(engine) return not engine.state:hasPerk("scout") end,
                      onChoose = function(engine) engine.state:addPerk("scout") end },
                    { id = "leave", text = L("say goodbye"), nextScene = "end" },
                },
            },
        },
    },
    { -- The Wandering Master
        title = L("The Master"),
        isAvailable = function(engine) return inRoom(engine) and engine.state:get("features.location.world") end,
        scenes = {
            start = {
                text = { L("an old wanderer arrives."), L("he smiles warmly and asks for lodgings for the night.") },
                notification = L("an old wanderer arrives"),
                blink = true,
                buttons = {
                    { id = "agree", text = L("agree"), cost = { ["cured meat"] = 100, fur = 100, torch = 1 }, nextScene = { [1] = "agree" } },
                    { id = "deny", text = L("turn him away"), nextScene = "end" },
                },
            },
            agree = {
                text = { L("in exchange, the wanderer offers his wisdom.") },
                buttons = {
                    perkButton("evasion", L("evasion"), "evasive"),
                    perkButton("precision", L("precision"), "precise"),
                    perkButton("force", L("force"), "barbarian"),
                    { id = "nothing", text = L("nothing"), nextScene = "end" },
                },
            },
        },
    },
    { -- The Sick Man
        title = L("The Sick Man"),
        isAvailable = function(engine) return inRoom(engine) and engine.state:get("stores.medicine", true) > 0 end,
        scenes = {
            start = {
                text = { L("a man hobbles up, coughing."), L("he begs for medicine.") },
                notification = L("a sick man hobbles up"),
                blink = true,
                buttons = {
                    { id = "help", text = L("give 1 medicine"), cost = { medicine = 1 },
                      notification = L("the man swallows the medicine eagerly"),
                      nextScene = { [0.1] = "alloy", [0.3] = "cells", [0.5] = "scales", [1.0] = "nothing" } },
                    { id = "ignore", text = L("tell him to leave"), nextScene = "end" },
                },
            },
            alloy = { text = { L("the man is thankful."), L("he leaves a reward."), L("some weird metal he picked up on his travels.") },
                onLoad = function(engine) engine.state:add('stores["alien alloy"]', 1) end, buttons = bye(nil, "bye") },
            cells = { text = { L("the man is thankful."), L("he leaves a reward."), L("some weird glowing boxes he picked up on his travels.") },
                onLoad = function(engine) engine.state:add('stores["energy cell"]', 3) end, buttons = bye(nil, "bye") },
            scales = { text = { L("the man is thankful."), L("he leaves a reward."), L("all he has are some scales.") },
                onLoad = function(engine) engine.state:add("stores.scales", 5) end, buttons = bye(nil, "bye") },
            nothing = { text = { L("the man expresses his thanks and hobbles off.") }, buttons = bye(nil, "bye") },
        },
    },
}
