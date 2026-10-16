--[[--
月读扩展描述：不是书源，只在月读首页加一个「小黑屋」入口组件，点按开始游戏。
契约见月读 examples/moonsource-demo.koplugin/moon_source.lua（api = 1，id = ext.<name>）。
没装月读时 KOReader 不会读本文件，插件照常从主菜单启动。
--]]
local _ = require("gettext")

local ID = "ext.adarkroom"

local widget = {
    id = "entry", -- 月读补成 ext.adarkroom.entry
    title = _("小黑屋"),
    icon = "local_fire_department",
    build = function(_ctx, w, h)
        local Button = require("ui/widget/button")
        local CenterContainer = require("ui/widget/container/centercontainer")
        local Geom = require("ui/geometry")
        return CenterContainer:new{
            dimen = Geom:new{ w = w, h = h },
            Button:new{
                text = _("小黑屋 · 继续游戏"),
                width = math.floor(w * 0.8),
                callback = function()
                    require("adarkroom.game").new(require("adarkroom.host.moon").new()):show()
                end,
            },
        }
    end,
}

return {
    api = 1,
    id = ID,
    provides = { source = false, home_widgets = { widget } },
}
