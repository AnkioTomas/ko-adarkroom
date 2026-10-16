-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
--[[--
月读宿主适配。月读扩展契约（book.koplugin/source/registry.lua，API = 1）只提供首页组件，
没有独立的界面 / 定时 API，所以定时仍走 KOReader UIManager；
  存档 / 设置：utils.settings.getSource("ext.adarkroom") 那张独立表（settings/ext.adarkroom.lua），
    改完 saveSource(ID) 落盘（就地修改同一张表，不会 reset），不写月读自己的分区；
  界面：优先 adarkroom.ui.moon_screen（月读主题组件），提示用月读 Toast；
    月读组件缺失（旧版月读 / 独立运行）时回落通用 KOReader 界面与 InfoMessage。
utils.settings 不存在时（不在月读里）整体退回 KOReader 宿主的 LuaSettings 存档。
--]]
local KOHost = require("adarkroom.host.koreader")
local Interface = require("adarkroom.host.interface")

local ID = "ext.adarkroom"

local Host = setmetatable({}, { __index = KOHost })
Host.__index = Host
Host.ID = ID

function Host.new(opts)
    local self = setmetatable({ opts = opts or {} }, Host)
    return Interface.check(self)
end

local function moonSettings()
    local ok, S = pcall(require, "utils.settings")
    if ok and type(S) == "table" and S.getSource and S.saveSource then return S end
end
local function conf() return moonSettings().getSource(ID) end
local function save() moonSettings().saveSource(ID) end

function Host:showScreen(view)
    local UIManager = require("ui/uimanager")
    if self.moon_ui == nil then
        local ok, mod = pcall(require, "adarkroom.ui.moon_screen")
        self.moon_ui = ok and mod or false
    end
    if not self.moon_ui then return KOHost.showScreen(self, view) end
    if self.widget then UIManager:close(self.widget) end
    local ok, widget = pcall(self.moon_ui.new, view, function()
        self.widget = nil
        if view.on_close then view.on_close() end
    end)
    if not ok then
        self.moon_ui = false -- 主题组件运行时出错：本次会话改用通用界面
        self.widget = nil
        return KOHost.showScreen(self, view)
    end
    self.widget = widget
    UIManager:show(widget)
end

function Host:notify(text)
    local ok, Toast = pcall(require, "ui.themes.widgets.toast")
    if ok and Toast and pcall(function() Toast:new{ text = text, timeout = 2 }:show() end) then return end
    return KOHost.notify(self, text)
end

function Host:loadState()
    if not moonSettings() then return KOHost.loadState(self) end
    return conf().state
end

function Host:saveState(state)
    if not moonSettings() then return KOHost.saveState(self, state) end
    conf().state = state
    save()
end

function Host:getSetting(key, default)
    if not moonSettings() then return KOHost.getSetting(self, key, default) end
    local v = (conf().settings or {})[key]
    if v == nil then return default end
    return v
end

function Host:setSetting(key, value)
    if not moonSettings() then return KOHost.setSetting(self, key, value) end
    local c = conf()
    c.settings = c.settings or {}
    c.settings[key] = value
    save()
end

return Host
