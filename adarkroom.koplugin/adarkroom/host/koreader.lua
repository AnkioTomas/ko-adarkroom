-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
--[[--
KOReader 宿主适配：UIManager 显示/定时，LuaSettings 存档（settings/adarkroom.lua）。
--]]
local Interface = require("adarkroom.host.interface")

local Host = {}
Host.__index = Host

local STATE_FILE = "adarkroom.lua"

function Host.new(opts)
    local self = setmetatable({ opts = opts or {} }, Host)
    return Interface.check(self)
end

function Host:_store()
    if not self.store then
        local DataStorage = require("datastorage")
        local LuaSettings = require("luasettings")
        local path = self.opts.state_path or (DataStorage:getSettingsDir() .. "/" .. STATE_FILE)
        self.store = LuaSettings:open(path)
    end
    return self.store
end

function Host:showScreen(view)
    local UIManager = require("ui/uimanager")
    local Screen = require("adarkroom.ui.screen")
    local old = self.widget
    self.widget = Screen.open(view, function()
        self.widget = nil
        if view.on_close then view.on_close() end
    end)
    UIManager:show(self.widget, "ui")
    if old then UIManager:close(old, "ui") end
end

--- 带小数的单调时钟：冷却进度条按它平滑走动（os.time 只有整秒）。
function Host:now()
    local ok, t = pcall(require, "ui/time")
    if ok and t and t.now and t.to_s then return t.to_s(t.now()) end
    return os.time()
end

function Host:closeScreen()
    if self.widget then
        require("ui/uimanager"):close(self.widget)
        self.widget = nil
    end
end

function Host:schedule(seconds, fn)
    require("ui/uimanager"):scheduleIn(seconds, fn)
    return fn
end

function Host:unschedule(handle)
    require("ui/uimanager"):unschedule(handle)
end

function Host:loadState() return self:_store():readSetting("state") end

function Host:saveState(state)
    local s = self:_store()
    s:saveSetting("state", state)
    s:flush()
end

function Host:getSetting(key, default)
    local v = self:_store():readSetting("setting_" .. key)
    if v == nil then return default end
    return v
end

function Host:setSetting(key, value)
    local s = self:_store()
    s:saveSetting("setting_" .. key, value)
    s:flush()
end

function Host:notify(text)
    local InfoMessage = require("ui/widget/infomessage")
    require("ui/uimanager"):show(InfoMessage:new{ text = text, timeout = 2 })
end

return Host
