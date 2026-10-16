-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- Port of A Dark Room script/events/marketing.js (author: mtownsend).
-- 阅读器上无法打开网页：「顺从」只记下标记并显示链接文字，然后结束事件。
local L = require("adarkroom.l10n")

local URL = "https://penrose.doublespeakgames.com/"

return {
    { -- Play Penrose!
        title = L("Penrose"),
        isAvailable = function(engine) return not engine.state:get("marketing.penrose") end,
        scenes = {
            start = {
                text = {
                    L("a strange thrumming, pounding and crashing. visions of people and places, of a huge machine and twisting curves."),
                    L("inviting. it would be so easy to give in, completely."),
                },
                notification = L("a strange thrumming, pounding and crashing. and then gone."),
                blink = true,
                buttons = {
                    { id = "give in", text = L("give in"), nextScene = "end",
                      onClick = function(engine)
                          engine.state:set("marketing.penrose", true)
                          engine:notify(nil, URL)
                      end },
                    { id = "ignore", text = L("ignore it"), nextScene = "end" },
                },
            },
        },
    },
}
