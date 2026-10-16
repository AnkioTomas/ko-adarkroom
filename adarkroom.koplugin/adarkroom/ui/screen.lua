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
    local rows = {}
    for _, b in ipairs(view.buttons or {}) do
        rows[#rows + 1] = { { text = b.text, enabled = b.enabled ~= false, callback = b.callback } }
    end
    local buttons = ButtonTable:new{ width = math.floor(w * 0.9), buttons = rows, zero_sep = true }
    local text_h = h - title:getSize().h - buttons:getSize().h - Screen:scaleBySize(40)
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
