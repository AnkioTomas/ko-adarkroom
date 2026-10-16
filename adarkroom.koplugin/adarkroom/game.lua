-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
--[[--
宿主入口外观：Game.new(host):show()。main.lua 和 moon_source.lua 都只调用这里。
--]]
local Game = {}
Game.__index = Game

function Game.new(host)
    return setmetatable({ engine = require("adarkroom.engine").new(host) }, Game)
end

function Game:show()
    self.engine:start()
    return self
end

function Game:close() self.engine:close() end

return Game
