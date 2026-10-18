-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
--[[--
小黑屋 KOReader 插件入口。游戏逻辑在 adarkroom/ 下，与宿主无关；宿主差异由 adarkroom.host.* 适配。
Port of A Dark Room (doublespeakgames/adarkroom), MPL-2.0.
--]]
local WidgetContainer = require("ui/widget/container/widgetcontainer")

-- KOReader 只在加载插件那一刻把插件目录放进 package.path；之后（菜单回调、月读首页点按）
-- 再 require("adarkroom.*") 需要自己补上。
local PLUGIN_DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
if not package.path:find(PLUGIN_DIR .. "/?.lua", 1, true) then
    package.path = PLUGIN_DIR .. "/?.lua;" .. package.path
end
local _ = require("adarkroom.i18n")


local ADarkRoom = WidgetContainer:extend{
    name = "adarkroom",
    is_doc_only = false,
}

function ADarkRoom:init()
    self.ui.menu:registerToMainMenu(self)
end

function ADarkRoom:addToMainMenu(menu_items)
    menu_items.adarkroom = {
        text = _("小黑屋"),
        sorting_hint = "tools",
        callback = function() self:launch() end,
    }
end

function ADarkRoom:launch()
    local host = require("adarkroom.host.koreader").new()
    require("adarkroom.game").new(host):show()
end

return ADarkRoom
