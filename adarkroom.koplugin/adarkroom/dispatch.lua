-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
--[[--
极简发布/订阅（替代原版 jQuery $.Dispatch）。
--]]
local unpack = unpack or table.unpack -- Lua 5.1/LuaJIT 与 5.2+ 兼容
local Dispatch = {}
Dispatch.__index = Dispatch

function Dispatch.new() return setmetatable({ topics = {} }, Dispatch) end

function Dispatch:subscribe(topic, fn)
    local list = self.topics[topic] or {}
    self.topics[topic] = list
    list[#list + 1] = fn
end

function Dispatch:unsubscribe(topic, fn)
    local list = self.topics[topic]
    if not list then return end
    for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) end end
end

function Dispatch:publish(topic, ...)
    local list = self.topics[topic]
    if not list then return end
    for _, fn in ipairs({ unpack(list) }) do fn(...) end
end

return Dispatch
