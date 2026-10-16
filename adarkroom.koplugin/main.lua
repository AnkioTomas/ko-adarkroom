--[[--
小黑屋 KOReader 插件入口。游戏逻辑在 adarkroom/ 下，与宿主无关；宿主差异由 adarkroom.host.* 适配。
Port of A Dark Room (doublespeakgames/adarkroom), MPL-2.0.
--]]
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

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
