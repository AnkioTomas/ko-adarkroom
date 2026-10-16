-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- Port of A Dark Room script/notifications.js.
--[[--
通知：发给当前模块的直接进日志；发给其它模块的进队列，切到该模块时再显示。
日志存进状态树 notifications，最多 MAX 条（新的在前）。
--]]
local Notifications = {}
Notifications.__index = Notifications
Notifications.MAX = 20

function Notifications.new(engine)
    return setmetatable({ engine = engine, queue = {} }, Notifications)
end

function Notifications:messages()
    local tree = self.engine.state.tree
    if type(tree.notifications) ~= "table" then tree.notifications = {} end
    return tree.notifications
end

function Notifications:printMessage(text)
    local list = self:messages()
    table.insert(list, 1, text)
    while #list > Notifications.MAX do table.remove(list) end
end

--- @param module table|nil 目标模块；nil 表示总是立即显示
function Notifications:notify(module, text, noQueue)
    if text == nil then return end
    if module ~= nil and self.engine.activeModule ~= module then
        if not noQueue then
            local key = module.name or tostring(module)
            self.queue[key] = self.queue[key] or {}
            table.insert(self.queue[key], text)
        end
    else
        self:printMessage(text)
    end
    self.engine:requestSave()
    self.engine:requestRender()
end

function Notifications:printQueue(module)
    local q = self.queue[module.name or tostring(module)]
    while q and #q > 0 do self:printMessage(table.remove(q, 1)) end
end

return Notifications
