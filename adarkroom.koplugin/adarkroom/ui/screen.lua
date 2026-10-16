-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
--[[--
通用游戏界面：标题 + 文本行 + 按钮列。只依赖 KOReader 基础控件。
按钮的分页由引擎做（engine:paginate），这里只负责显示；文本区（库存 + 通知日志）
用 ScrollTextWidget，内容超出时可上下滑动 / 翻页键滚动。
--]]
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Device = require("device")
local Font = require("ui/font")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local GameScreen = InputContainer:extend{ covers_fullscreen = true }

-- 注意不能叫 new：会覆盖 InputContainer:new，GameScreen:new{} 变成无限尾调用（模拟器里卡死）
function GameScreen.open(view, on_close)
    return GameScreen:new{ view = view, on_close = on_close }
end

function GameScreen:init()
    local w, h = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = w, h = h }
    local view = self.view
    local title = TitleBar:new{
        width = w, title = view.title or "",
        close_callback = function() self:onClose() end,
    }
    -- 按钮项三种：单个按钮 { text, callback, enabled? }；一行按钮 { {..}, {..} }；分组标题 { label }。
    -- 连续的单个按钮两两并排，省竖向空间。
    local function cell(b) return { text = b.text, enabled = b.enabled ~= false, callback = b.callback } end
    local rows, pending = {}, nil
    local function flush()
        if pending then rows[#rows + 1] = { cell(pending) } pending = nil end
    end
    for _, b in ipairs(view.buttons or {}) do
        if b.label then
            flush()
            rows[#rows + 1] = { { text = b.label, enabled = false, callback = function() end } }
        elseif b[1] then
            flush()
            local row = {}
            for _, c in ipairs(b) do row[#row + 1] = cell(c) end
            rows[#rows + 1] = row
        elseif pending then
            rows[#rows + 1] = { cell(pending), cell(b) }
            pending = nil
        else
            pending = b
        end
    end
    flush()
    local buttons = ButtonTable:new{ width = math.floor(w * 0.9), buttons = rows, zero_sep = true }
    -- 世界地图 / 太空：等宽字体逐行绘制（view.map = { "....", ... }），见 ui/maptext.lua；
    -- 屏幕放不下时逐级缩小字号。
    local fixed = title:getSize().h + buttons:getSize().h + Screen:scaleBySize(40)
    local map, map_h = nil, 0
    if view.map then
        local MapText = require("adarkroom.ui.maptext")
        for _, size in ipairs({ 22, 18, 15, 12, 10 }) do
            if map then map:free() end
            map, map_h = MapText.build(view.map, size, math.floor(w * 0.9))
            if h - fixed - map_h >= Screen:scaleBySize(60) then break end
        end
    end
    local text_h = h - fixed - map_h
    local text
    if text_h >= Screen:scaleBySize(24) then
        text = ScrollTextWidget:new{
            text = table.concat(view.lines or {}, "\n"),
            face = Font:getFace("cfont", 20),
            width = math.floor(w * 0.9),
            height = text_h,
            dialog = self,
        }
    end
    self[1] = FrameContainer:new{
        width = w, height = h, padding = 0, bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "center",
            title,
            VerticalSpan:new{ width = Screen:scaleBySize(20) },
            map or VerticalSpan:new{ width = 0 },
            text or VerticalSpan:new{ width = 0 },
            VerticalSpan:new{ width = Screen:scaleBySize(20) },
            buttons,
        },
    }
end

function GameScreen:onClose()
    UIManager:close(self)
    if self.on_close then self.on_close() end
    return true
end

return GameScreen
