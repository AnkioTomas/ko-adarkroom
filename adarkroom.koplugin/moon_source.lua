-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
--[[--
月读扩展描述：不是书源，只在月读首页加一个「小黑屋」入口组件，点按开始游戏。
契约见月读 examples/moonsource-demo.koplugin/moon_source.lua（api = 1，id = ext.<name>）。
没装月读时 KOReader 不会读本文件，插件照常从主菜单启动。
--]]
local _ = require("gettext")

-- KOReader 只在加载插件那一刻把插件目录放进 package.path；之后（菜单回调、月读首页点按）
-- 再 require("adarkroom.*") 需要自己补上。
local PLUGIN_DIR = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
if not package.path:find(PLUGIN_DIR .. "/?.lua", 1, true) then
    package.path = PLUGIN_DIR .. "/?.lua;" .. package.path
end


local ID = "ext.adarkroom"

local widget = {
    id = "entry", -- 月读补成 ext.adarkroom.entry
    title = _("小黑屋"),
    icon = "local_fire_department", -- 已核对：在月读 ui/themes/widgets/icon/names.lua（Material Symbols）里
    build = function(_ctx, w, h)
        -- 月读主题按钮（跟随首页主题）；拿不到就用 KOReader 自带按钮
        local okb, Button = pcall(require, "ui.themes.widgets.button")
        if not okb then Button = require("ui/widget/button") end
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
