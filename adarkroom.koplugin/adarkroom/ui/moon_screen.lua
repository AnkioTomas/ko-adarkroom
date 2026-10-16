-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
--[[--
月读风格的游戏界面：与 ui/screen.lua 同一份 view 描述，控件换成月读主题组件
（book.koplugin/ui/themes：令牌取当前主题，纸本 / 高对比 / 柔和自动跟随）。
  标题行  淡色标题 + ✕（不画标题栏框，见 ui/layout.lua）
  按钮    ui.themes.widgets.button    Button:new{ text, width, enabled, callback }
  分组名  ui.themes.widgets.text      Text.line("caption", …)；正文字号取 Text.face("body")
  翻页条  ui.themes.widgets.pager     Pager.widget{ page, pages, on_prev, on_next }
  颜色    ui.themes                   Theme.current().color.page / ink，尺寸经 Theme.px
任何一个模块 require 失败都会让本文件加载失败，月读宿主据此回落到通用界面。
--]]
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local Theme = require("ui.themes")
local MButton = require("ui.themes.widgets.button")
local MText = require("ui.themes.widgets.text")
local MPager = require("ui.themes.widgets.pager")
local Layout = require("adarkroom.ui.layout")
local Screen = Device.screen

-- 全屏浮层：盖住月读首页（含底部导航），✕ 关闭后回到首页
local MoonScreen = InputContainer:extend{ covers_fullscreen = true, modal = true }

-- 注意不能叫 new：会覆盖 InputContainer:new，MoonScreen:new{} 变成无限尾调用（模拟器里卡死）
function MoonScreen.open(view, on_close)
    return MoonScreen:new{ view = view, on_close = on_close }
end

local function kit()
    local t = Theme.current()
    local c = t.color
    local C = Blitbuffer.Color8
    return {
        px = Theme.px,
        bg = C(c.page), ink = C(c.ink),
        greys = { C(c.muted), C(c.faint), C(c.disabled) },
        face = MText.face("body"), face_small = MText.face("body"), face_title = MText.face("body"),
        button = function(text, w, enabled, cb)
            return MButton:new{ text = text, width = w, enabled = enabled, callback = cb }
        end,
        caption = function(text, w) return MText.line("caption", text, { width = w, color = c.faint }) end,
        pager = function(p, w)
            return MPager.widget{ width = w, page = p.page, pages = p.pages, on_prev = p.prev, on_next = p.next }
        end,
    }
end

function MoonScreen:init()
    local w, h = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = w, h = h }
    local k = kit()
    k.bars = {}
    self[1] = FrameContainer:new{
        width = w, height = h, padding = 0, bordersize = 0, background = k.bg,
        Layout.build(k, self.view, w, h, function() self:onClose() end),
    }
    self.bars = k.bars
end

-- 显示后才开始走冷却条（此时各条的屏幕坐标已在首次绘制时记下）；关掉就停
function MoonScreen:onShow() Layout.start(self, self.bars) end
function MoonScreen:onCloseWidget() Layout.stop(self) end

function MoonScreen:onClose()
    UIManager:close(self, "ui") -- 整屏刷新，回到月读首页时不留残影
    if self.on_close then self.on_close() end
    return true
end

return MoonScreen
