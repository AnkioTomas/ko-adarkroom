-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
--[[--
月读首页「小黑屋」卡片：图标 + 标题 + 存档摘要（火堆、所在地、木头、人口），整张卡点按进入游戏。
样式照月读自带组件：ui.themes 的 card 表面（边框 / 圆角）、Text 字号角色、灰度令牌、Material 图标。
卡片在每次绘制时比对存档摘要，变了就原地重建，所以从游戏返回首页时显示的是最新进度。
月读主题组件拿不到时回落到 KOReader 自带控件（FrameContainer + TextWidget）。
--]]
local L = require("adarkroom.l10n")

local Card = {}

local FIRE = { "dead", "smoldering", "flickering", "burning", "roaring" }

local function get(t, ...)
    for _, k in ipairs({ ... }) do
        if type(t) ~= "table" then return nil end
        t = t[k]
    end
    return t
end

--- 由存档表算出卡片文案（纯函数，便于无头测试）。
---@param state table|nil 存档（host:loadState() 的返回值）
---@return { title: string, line1: string, line2: string, new_game: boolean }
function Card.summary(state)
    if next(L.table) == nil and L.locale ~= "en" then L.load(L.locale) end -- 首页上游戏引擎还没加载过语言表
    local out = { title = L("A Dark Room"), new_game = true }
    local started = type(state) == "table" and type(state.game) == "table"
        and (get(state, "game", "builder", "level") or -1) >= 0 or (get(state, "stores", "wood") or 0) > 0
    if not started then
        out.line1 = "炉膛冰冷，黑暗里只剩你自己。"
        local prev = get(state, "previous", "score")
        out.line2 = prev and prev > 0 and ("上一局总分 " .. prev .. " · 点按重新开始") or "点按生火，开始游戏"
        return out
    end
    out.new_game = false
    local fire = tonumber(get(state, "game", "fire", "value")) or 0
    fire = math.max(0, math.min(#FIRE - 1, math.floor(fire)))
    local huts = tonumber(get(state, "game", "buildings", "hut")) or 0
    local where
    if state.expedition then where = "远征途中"
    elseif get(state, "features", "location", "outside") then
        if huts == 0 then where = L("A Silent Forest")
        elseif huts == 1 then where = L("A Lonely Hut")
        elseif huts <= 4 then where = L("A Tiny Village")
        elseif huts <= 8 then where = L("A Modest Village")
        elseif huts <= 14 then where = L("A Large Village")
        else where = L("A Raucous Village") end
    else
        where = fire < 2 and L("A Dark Room") or L("A Firelit Room")
    end
    out.line1 = L("the fire is {0}", L(FIRE[fire + 1])) .. " · " .. where
    local parts = { L("wood") .. " " .. math.floor(tonumber(get(state, "stores", "wood")) or 0) }
    if huts > 0 then
        parts[#parts + 1] = L("pop ") .. (tonumber(get(state, "game", "population")) or 0) .. "/" .. huts * 4
    end
    out.line2 = table.concat(parts, " · ")
    return out
end

local function key(s) return s.line1 .. "\31" .. s.line2 end

--- 月读主题版卡片内容。
local function themed(s, w, h)
    local Theme = require("ui.themes")
    local Box = require("ui.themes.widgets.box")
    local Text = require("ui.themes.widgets.text")
    local Icon = require("ui.themes.widgets.icon")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local Geom = require("ui/geometry")
    local t = Theme.current()
    local pad = Theme.px(t.space.md)
    local gap = Theme.px(t.space.md)
    local icon_size = 40
    local fire = Icon.widget{ name = "local_fire_department", size = icon_size }
    local chevron = Icon.widget{ name = "chevron_right", size = 24, color = nil }
    local icon_w = Theme.px(icon_size)
    local chev_w = Theme.px(24)
    local text_w = math.max(1, w - pad * 2 - icon_w - chev_w - gap * 2)
    local col = VerticalGroup:new{
        align = "left",
        Text.line("title", s.title, { width = text_w }),
        VerticalSpan:new{ width = Theme.px(t.space.xs) },
        Text.line("body", s.line1, { width = text_w, color = t.color.muted }),
        VerticalSpan:new{ width = Theme.px(t.space.xs) },
        Text.line("caption", s.line2, { width = text_w, color = t.color.faint }),
    }
    local row = HorizontalGroup:new{
        align = "center",
        fire, HorizontalSpan:new{ width = gap },
        LeftContainer:new{ dimen = Geom:new{ w = text_w, h = col:getSize().h }, col },
        HorizontalSpan:new{ width = gap }, chevron,
    }
    return Box:new{ style = t.card, width = w, height = h, padding = pad, row }
end

--- 没有月读主题时的朴素版本。
local function plain(s, w, h)
    local Blitbuffer = require("ffi/blitbuffer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local TextWidget = require("ui/widget/textwidget")
    local Font = require("ui/font")
    local inner = w - 24
    return FrameContainer:new{
        width = w, height = h, bordersize = 1, radius = 4, padding = 10, background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            TextWidget:new{ text = s.title, face = Font:getFace("tfont", 22), bold = true, max_width = inner },
            TextWidget:new{ text = s.line1, face = Font:getFace("cfont", 18), max_width = inner },
            TextWidget:new{ text = s.line2, face = Font:getFace("cfont", 15), fgcolor = Blitbuffer.COLOR_GRAY_5, max_width = inner },
        },
    }
end

local function content(s, w, h)
    local ok, wdg = pcall(themed, s, w, h)
    if ok and wdg then return wdg end
    return plain(s, w, h)
end

--- 首页组件高度：标题 + 两行说明 + 内边距。
function Card.height()
    local ok, h = pcall(function()
        local Theme = require("ui.themes")
        local Text = require("ui.themes.widgets.text")
        local t = Theme.current()
        local lines = Text.line("title", "小"):getSize().h + Text.line("body", "小"):getSize().h
            + Text.line("caption", "小"):getSize().h
        return lines + Theme.px(t.space.xs) * 2 + Theme.px(t.space.md) * 2 + 2
    end)
    return ok and h or 110
end

---@param load fun(): table|nil 读存档
---@param open fun() 打开游戏
function Card.build(w, h, load, open)
    local Geom = require("ui/geometry")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local GestureRange = require("ui/gesturerange")
    local function read() local ok, st = pcall(load) return Card.summary(ok and st or nil) end
    local s = read()
    local card = InputContainer:new{ dimen = Geom:new{ x = 0, y = 0, w = w, h = h }, content(s, w, h) }
    card.summary_key = key(s)
    card.ges_events = { TapAdarkroomCard = { GestureRange:new{ ges = "tap", range = function() return card.dimen end } } }
    function card:onTapAdarkroomCard() open() return true end
    local paintTo = card.paintTo
    function card:paintTo(bb, x, y)
        local now = read()
        if key(now) ~= self.summary_key then
            self.summary_key = key(now)
            self[1] = content(now, w, h)
        end
        return paintTo(self, bb, x, y)
    end
    return card
end

return Card
