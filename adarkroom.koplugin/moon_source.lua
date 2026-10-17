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

local function openGame()
    require("adarkroom.game").new(require("adarkroom.host.moon").new()):show()
end

local function loadSave()
    return require("adarkroom.host.moon").new():loadState()
end

local widget = {
    id = "entry", -- 月读补成 ext.adarkroom.entry
    title = _("小黑屋"),
    icon = "local_fire_department", -- 已核对：在月读 ui/themes/widgets/icon/names.lua（Material Symbols）里
    heightRange = function()
        local ok, Card = pcall(require, "adarkroom.ui.moon_card")
        return { height = ok and Card.height() or 110 }
    end,
    build = function(_ctx, w, h)
        -- 存档摘要卡片（月读主题）；卡片模块出错时退回一个普通按钮，入口不丢
        local ok, card = pcall(function() return require("adarkroom.ui.moon_card").build(w, h, loadSave, openGame) end)
        if ok and card then return card end
        local okb, Button = pcall(require, "ui.themes.widgets.button")
        if not okb then Button = require("ui/widget/button") end
        local CenterContainer = require("ui/widget/container/centercontainer")
        local Geom = require("ui/geometry")
        return CenterContainer:new{
            dimen = Geom:new{ w = w, h = h },
            Button:new{ text = _("小黑屋"), width = math.floor(w * 0.8), callback = openGame },
        }
    end,
}

return {
    api = 1,
    id = ID,
    provides = {
        source = false,
        -- 顶部下拉快捷面板：月读只开放「动作开关」挂点（title / icon / run），点一下全屏打开游戏
        features = { panel = { actions = function()
            return { {
                id = "play", scope = "desktop", title = _("小黑屋"), icon = "local_fire_department",
                run = function() pcall(openGame) end,
            } }
        end } },
        home_widgets = { widget },
    },
}
