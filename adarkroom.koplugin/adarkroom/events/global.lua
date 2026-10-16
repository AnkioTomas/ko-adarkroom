-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- Port of A Dark Room script/events/global.js.
local L = require("adarkroom.l10n")

return {
    { -- The Thief
        title = L("The Thief"),
        isAvailable = function(engine)
            local m = engine.activeModule
            return m ~= nil and (m.name == "room" or m.name == "outside")
                and engine.state:get("game.thieves") == 1
        end,
        scenes = {
            start = {
                text = {
                    L("the villagers haul a filthy man out of the store room."),
                    L("say his folk have been skimming the supplies."),
                    L("say he should be strung up as an example."),
                },
                notification = L("a thief is caught"),
                blink = true,
                buttons = {
                    { id = "kill", text = L("hang him"), nextScene = { [1] = "hang" } },
                    { id = "spare", text = L("spare him"), nextScene = { [1] = "spare" } },
                },
            },
            hang = {
                text = {
                    L("the villagers hang the thief high in front of the store room."),
                    L("the point is made. in the next few days, the missing supplies are returned."),
                },
                onLoad = function(engine)
                    local sm = engine.state
                    sm:set("game.thieves", 2)
                    sm:remove("income.thieves")
                    sm:addM("stores", sm:get("game.stolen") or {})
                end,
                buttons = { { id = "leave", text = L("leave"), nextScene = "end" } },
            },
            spare = {
                text = {
                    L("the man says he's grateful. says he won't come around any more."),
                    L("shares what he knows about sneaking before he goes."),
                },
                onLoad = function(engine)
                    local sm = engine.state
                    sm:set("game.thieves", 2)
                    sm:remove("income.thieves")
                    sm:addPerk("stealthy")
                end,
                buttons = { { id = "leave", text = L("leave"), nextScene = "end" } },
            },
        },
    },
}
