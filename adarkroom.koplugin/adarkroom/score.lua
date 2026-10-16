-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- Port of A Dark Room script/scoring.js.
local Prestige = require("adarkroom.prestige")

local Score = {}

Score.factor = { 1, 1.5, 1, 2, 2, 3, 3, 2, 2, 2, 2, 1.5, 1, 1, 10, 30, 50, 100, 150, 150, 3, 3, 5, 4 }

function Score.calculateScore(engine)
    local sm = engine.state
    local stores = Prestige.getStores(engine, false)
    local full = 0
    for i, f in ipairs(Score.factor) do full = full + (stores[i] or 0) * f end
    full = full + sm:get('stores["alien alloy"]', true) * 10
    full = full + sm:get('stores["fleet beacon"]', true) * 500
    full = full + require("adarkroom.ship").getMaxHull(engine) * 50
    return math.floor(full)
end

function Score.save(engine)
    engine.state:set("playStats.score", Score.calculateScore(engine))
end

function Score.totalScore(engine)
    return engine.state:get("previous.score", true) + Score.calculateScore(engine)
end

return Score
