--[[--
通用游戏界面：标题 + 文本行 + 按钮列。只依赖 KOReader 基础控件。
--]]
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Device = require("device")
local Font = require("ui/font")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local GameScreen = InputContainer:extend{ covers_fullscreen = true }

function GameScreen.new(view, on_close)
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
    -- 世界地图：等宽字体逐行绘制（view.map = { "....", ... }）
    local map
    if view.map then
        map = TextBoxWidget:new{
            text = table.concat(view.map, "\n"),
            face = Font:getFace("infont", 18),
            width = math.floor(w * 0.9),
            alignment = "center",
        }
    end
    local map_h = map and map:getSize().h or 0
    local text_h = h - title:getSize().h - buttons:getSize().h - map_h - Screen:scaleBySize(40)
    local text = TextBoxWidget:new{
        text = table.concat(view.lines or {}, "\n"),
        face = Font:getFace("cfont", 20),
        width = math.floor(w * 0.9),
        height = math.max(text_h, Screen:scaleBySize(60)),
        height_adjust = false,
    }
    self[1] = FrameContainer:new{
        width = w, height = h, padding = 0, bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "center",
            title,
            VerticalSpan:new{ width = Screen:scaleBySize(20) },
            map or VerticalSpan:new{ width = 0 },
            text,
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
