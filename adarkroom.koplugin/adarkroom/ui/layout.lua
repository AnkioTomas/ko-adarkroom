-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
--[[--
两种界面（通用 KOReader / 月读主题）共用的排版。控件由调用方的 kit 提供：
  kit = { px, bg, ink, greys = {g1,g2,g3}, face, face_small, face_title,
          button(text, w, enabled, cb), caption(text, w), pager(p, w)|nil }
排版原则（墨水屏、无动画）：
  · 顶部只有一行淡色标题和一个 ✕，不画标题栏框和分割线；
  · 内容只有存在时才出现（开局只有消息和一个按钮）；
  · 消息新的在上，越旧越淡（三级灰），不画滚动条，放不下的旧消息直接不显示；
  · 冷却用按钮下方的细进度条表示（引擎每隔几秒重绘一次）；
  · 屏幕够宽时像原版一样左列按钮、右列库存与消息，否则上下堆叠，按钮在下方。
--]]
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Layout = {}

--- 固定尺寸、子件贴左上角的容器（LeftContainer 会垂直居中）。
local TopLeft = WidgetContainer:extend{}
function TopLeft:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    if self[1] then self[1]:paintTo(bb, x, y) end
end
local function box(w, h, child)
    return TopLeft:new{ dimen = Geom:new{ w = w, h = h }, child or VerticalSpan:new{ width = 0 } }
end

--- 一行标题 + 右侧 ✕（整块点击区）。
local function header(kit, w, title, on_close)
    local px = kit.px
    local h = px(44)
    local x = TextWidget:new{ text = "✕", face = kit.face_title, fgcolor = kit.greys[1] }
    local xw = px(52)
    local close = InputContainer:new{ dimen = Geom:new{ x = 0, y = 0, w = xw, h = h },
        require("ui/widget/container/centercontainer"):new{ dimen = Geom:new{ w = xw, h = h }, x } }
    close.ges_events = { TapClose = { GestureRange:new{ ges = "tap", range = function() return close.dimen end } } }
    function close:onTapClose() on_close() return true end
    local tw = w - xw - px(16)
    local t = TextWidget:new{ text = title or "", face = kit.face_title, fgcolor = kit.greys[2], max_width = tw }
    return HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = px(16) }, LeftContainer:new{ dimen = Geom:new{ w = tw, h = h }, t }, close }, h
end

--- 冷却细条：剩余比例越小条越短；无冷却时留同样高度的空白，免得按钮跳动。
local function bar(kit, w, cd)
    local h = kit.px(3)
    if not cd or not cd.total or cd.total <= 0 or (cd.left or 0) <= 0 then return VerticalSpan:new{ width = h } end
    local frac = math.max(0.02, math.min(1, cd.left / cd.total))
    return box(w, h, LineWidget:new{ dimen = Geom:new{ w = math.floor(w * frac), h = h }, background = kit.greys[2] })
end

--- 按钮区：行由引擎排好（engine:paginate）。
local function buttons(kit, w, rows)
    local px = kit.px
    local gap = px(6)
    local col = VerticalGroup:new{ align = "left" }
    local function add(wd)
        if #col > 0 then col[#col + 1] = VerticalSpan:new{ width = gap } end
        col[#col + 1] = wd
    end
    for _, r in ipairs(rows or {}) do
        if r.label then
            add(kit.caption(r.label, w))
        elseif r.pager and kit.pager then
            add(kit.pager(r.pager, w))
        else
            local cells = r[1] and r or { r }
            local n = #cells
            local bw = math.floor((w - gap * (n - 1)) / n)
            local hg = HorizontalGroup:new{ align = "top" }
            for i, c in ipairs(cells) do
                if i > 1 then hg[#hg + 1] = HorizontalSpan:new{ width = gap } end
                hg[#hg + 1] = VerticalGroup:new{ align = "left",
                    kit.button(c.text, bw, c.enabled ~= false, c.callback), VerticalSpan:new{ width = px(2) },
                    bar(kit, bw, c.cooldown) }
            end
            add(hg)
        end
    end
    return col
end

--- 消息：新的在上，越旧越淡；只放得下多少显示多少。
local function log(kit, w, msgs, max_h)
    local col = VerticalGroup:new{ align = "left" }
    local used = 0
    for i, m in ipairs(msgs or {}) do
        local color = i <= 2 and kit.ink or i <= 5 and kit.greys[1] or i <= 9 and kit.greys[2] or kit.greys[3]
        local tb = TextBoxWidget:new{ text = m, face = kit.face, width = w, fgcolor = color, bgcolor = kit.bg }
        local h = tb:getSize().h + kit.px(4)
        if used + h > max_h then tb:free() break end
        if #col > 0 then col[#col + 1] = VerticalSpan:new{ width = kit.px(4) } end
        col[#col + 1] = tb
        used = used + h
    end
    return col
end

--- 库存 / 状态：没有就不画；高度超出时省略号截断。
local function info(kit, w, lines, max_h)
    if not lines or #lines == 0 or max_h < kit.px(24) then return nil end
    local tb = TextBoxWidget:new{ text = table.concat(lines, "\n"), face = kit.face_small, width = w,
        fgcolor = kit.ink, bgcolor = kit.bg }
    if tb:getSize().h > max_h then
        tb:free()
        tb = TextBoxWidget:new{ text = table.concat(lines, "\n"), face = kit.face_small, width = w, height = max_h,
            height_overflow_show_ellipsis = true, fgcolor = kit.ink, bgcolor = kit.bg }
    end
    return tb
end

local function map(kit, w, lines, max_h)
    if not lines then return nil, 0 end
    local MapText = require("adarkroom.ui.maptext")
    local m, mh
    for _, size in ipairs({ 22, 18, 15, 12, 10 }) do
        if m then m:free() end
        m, mh = MapText.build(lines, size, w, kit.ink, kit.bg)
        if mh <= max_h then break end
    end
    return m, mh
end

--- @return widget 全屏内容（不含底色框）
function Layout.build(kit, view, w, h, on_close)
    local px = kit.px
    local head, head_h = header(kit, w, view.title, on_close)
    local margin = px(16)
    local gap = px(14)
    local body_h = h - head_h - px(12)
    local wide = w >= h * 0.95 and w >= px(600)
    local root = VerticalGroup:new{ align = "left", head, VerticalSpan:new{ width = px(4) } }
    if wide then
        local left_w = math.floor((w - margin * 2 - gap) * 0.45)
        local right_w = w - margin * 2 - gap - left_w
        local btns = buttons(kit, left_w, view.buttons)
        local right = VerticalGroup:new{ align = "left" }
        local free = body_h
        local m, mh = map(kit, right_w, view.map, math.floor(body_h * 0.6))
        if m then right[#right + 1] = m right[#right + 1] = VerticalSpan:new{ width = gap } free = free - mh - gap end
        local inf = info(kit, right_w, view.info, math.floor(free * 0.55))
        if inf then right[#right + 1] = inf right[#right + 1] = VerticalSpan:new{ width = gap } free = free - inf:getSize().h - gap end
        right[#right + 1] = log(kit, right_w, view.log, free)
        root[#root + 1] = HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = margin },
            box(left_w, body_h, btns), HorizontalSpan:new{ width = gap }, box(right_w, body_h, right) }
        return root
    end
    local cw = w - margin * 2
    local btns = buttons(kit, cw, view.buttons)
    local free = body_h - btns:getSize().h - gap
    local col = VerticalGroup:new{ align = "left" }
    local m, mh = map(kit, cw, view.map, math.floor(free * 0.65))
    if m then col[#col + 1] = m col[#col + 1] = VerticalSpan:new{ width = gap } free = free - mh - gap end
    local inf = info(kit, cw, view.info, math.floor(free * 0.5))
    if inf then col[#col + 1] = inf col[#col + 1] = VerticalSpan:new{ width = gap } free = free - inf:getSize().h - gap end
    col[#col + 1] = log(kit, cw, view.log, free)
    local top_h = body_h - btns:getSize().h - gap
    root[#root + 1] = HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = margin },
        VerticalGroup:new{ align = "left", box(cw, top_h, col), VerticalSpan:new{ width = gap }, btns } }
    return root
end

return Layout
