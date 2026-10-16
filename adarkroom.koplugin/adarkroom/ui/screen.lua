-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
--[[--
通用游戏界面：标题 + 文本行 + 按钮列。只依赖 KOReader 基础控件。
按钮的分页由引擎做（engine:paginate）；排版见 ui/layout.lua，这里只提供 KOReader 控件。
--]]
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Layout = require("adarkroom.ui.layout")
local Screen = Device.screen

local GameScreen = InputContainer:extend{ covers_fullscreen = true }

-- 注意不能叫 new：会覆盖 InputContainer:new，GameScreen:new{} 变成无限尾调用（模拟器里卡死）
function GameScreen.open(view, on_close)
    return GameScreen:new{ view = view, on_close = on_close }
end

local function kit()
    local px = function(n) return Screen:scaleBySize(n) end
    return {
        px = px,
        bg = Blitbuffer.COLOR_WHITE, ink = Blitbuffer.COLOR_BLACK,
        greys = { Blitbuffer.Color8(0x55), Blitbuffer.Color8(0x88), Blitbuffer.Color8(0xAA) },
        face = Font:getFace("cfont", 20), face_small = Font:getFace("cfont", 18), face_title = Font:getFace("cfont", 20),
        button = function(text, w, enabled, cb)
            return Button:new{ text = text, width = w, enabled = enabled, callback = cb,
                bordersize = px(1), radius = px(4), text_font_size = 18 }
        end,
        caption = function(text, w)
            return TextWidget:new{ text = text, face = Font:getFace("cfont", 15), fgcolor = Blitbuffer.Color8(0x88), max_width = w }
        end,
    }
end

function GameScreen:init()
    local w, h = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = w, h = h }
    local k = kit()
    k.bars = {}
    self[1] = FrameContainer:new{
        width = w, height = h, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE,
        Layout.build(k, self.view, w, h, function() self:onClose() end),
    }
    self.bars = k.bars
end

-- 显示后才开始走冷却条（此时各条的屏幕坐标已在首次绘制时记下）；关掉就停
function GameScreen:onShow() Layout.start(self, self.bars) end
function GameScreen:onCloseWidget() Layout.stop(self) end

function GameScreen:onClose()
    UIManager:close(self, "ui") -- 整屏刷新，回到下层（月读首页 / 文件管理器）时不留残影
    if self.on_close then self.on_close() end
    return true
end

return GameScreen
