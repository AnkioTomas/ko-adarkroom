-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
--[[--
月读风格的游戏界面：与 ui/screen.lua 同一份 view 描述，控件换成月读主题组件
（book.koplugin/ui/themes：令牌取当前主题，纸本 / 高对比 / 柔和自动跟随）。
  标题栏  ui.themes.widgets.titlebar  TitleBar.widget{ title, right_icon = "close" }
  按钮    ui.themes.widgets.button    Button:new{ text, width, enabled, callback }
  分组名  ui.themes.widgets.text      Text.line("caption", …)；正文字号取 Text.face("body")
  翻页条  ui.themes.widgets.pager     Pager.widget{ page, pages, on_prev, on_next }
  颜色    ui.themes                   Theme.current().color.page / ink，尺寸经 Theme.px
任何一个模块 require 失败都会让本文件加载失败，月读宿主据此回落到通用界面。
--]]
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Theme = require("ui.themes")
local MButton = require("ui.themes.widgets.button")
local MText = require("ui.themes.widgets.text")
local MTitleBar = require("ui.themes.widgets.titlebar")
local MPager = require("ui.themes.widgets.pager")
local Screen = Device.screen

local MoonScreen = InputContainer:extend{ covers_fullscreen = true }

-- 注意不能叫 new：会覆盖 InputContainer:new，MoonScreen:new{} 变成无限尾调用（模拟器里卡死）
function MoonScreen.open(view, on_close)
    return MoonScreen:new{ view = view, on_close = on_close }
end

function MoonScreen:init()
    local t = Theme.current()
    local page_bg = Blitbuffer.Color8(t.color.page)
    local ink = Blitbuffer.Color8(t.color.ink)
    local w, h = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = w, h = h }
    local view = self.view
    local cw = math.floor(w * 0.92)
    local gap = Theme.px(4)
    local title = MTitleBar.widget{ width = w, title = view.title or "",
        right_icon = "close", right_callback = function() self:onClose() end }

    local rows = VerticalGroup:new{ align = "center" }
    local function add(widget)
        if #rows > 0 then rows[#rows + 1] = VerticalSpan:new{ width = gap } end
        rows[#rows + 1] = widget
    end
    -- view.buttons 已由引擎排成行（engine:paginate）；保险起见单个按钮也当一行
    for _, r in ipairs(view.buttons or {}) do
        if r.label then
            add(LeftContainer:new{ dimen = Geom:new{ w = cw, h = MText.line("caption", r.label):getSize().h },
                MText.line("caption", r.label, { width = cw }) })
        elseif r.pager then
            local p = r.pager
            add(MPager.widget{ width = cw, page = p.page, pages = p.pages, on_prev = p.prev, on_next = p.next })
        else
            local cells = r[1] and r or { r }
            local n = #cells
            local bw = math.floor((cw - gap * (n - 1)) / n)
            local hg = HorizontalGroup:new{ align = "center" }
            for i, c in ipairs(cells) do
                if i > 1 then hg[#hg + 1] = HorizontalSpan:new{ width = gap } end
                hg[#hg + 1] = MButton:new{ text = c.text, width = bw, enabled = c.enabled ~= false,
                    callback = c.callback }
            end
            add(hg)
        end
    end

    -- 地图（ui/maptext.lua）：放不下时逐级缩小字号（同 ui/screen.lua）
    local fixed = title:getSize().h + rows:getSize().h + Theme.px(32)
    local map, map_h = nil, 0
    if view.map then
        local MapText = require("adarkroom.ui.maptext")
        for _, size in ipairs({ 22, 18, 15, 12, 10 }) do
            if map then map:free() end
            map, map_h = MapText.build(view.map, size, cw, ink, page_bg)
            if h - fixed - map_h >= Theme.px(48) then break end
        end
    end
    local text_h = h - fixed - map_h
    local text
    if text_h >= Theme.px(20) then
        text = ScrollTextWidget:new{
            text = table.concat(view.lines or {}, "\n"),
            face = MText.face("body"), fgcolor = ink, bgcolor = page_bg,
            width = cw, height = text_h, dialog = self,
        }
    end
    self[1] = FrameContainer:new{
        width = w, height = h, padding = 0, bordersize = 0, background = page_bg,
        VerticalGroup:new{
            align = "center",
            title,
            VerticalSpan:new{ width = Theme.px(8) },
            map or VerticalSpan:new{ width = 0 },
            text or VerticalSpan:new{ width = 0 },
            VerticalSpan:new{ width = Theme.px(8) },
            rows,
        },
    }
end

function MoonScreen:onClose()
    UIManager:close(self)
    if self.on_close then self.on_close() end
    return true
end

return MoonScreen
