-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
--[[--
等宽字符地图控件（世界地图 / 太空网格），两种界面共用。
居中对齐的 TextBoxWidget 会吃掉行首行尾空白，各行就对不齐了；这里改为左对齐、
宽度按一行实际字宽量出来，再整体放进 CenterContainer 居中。
--]]
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")

local MapText = {}

--- @return widget, height
function MapText.build(lines, size, maxw, fg, bg)
    local face = Font:getFace("infont", size)
    local cols = 0
    for _, l in ipairs(lines) do cols = math.max(cols, #l) end
    local probe = TextWidget:new{ text = string.rep("M", math.max(cols, 1)), face = face }
    local tw = math.min(maxw, probe:getSize().w + 2)
    probe:free()
    local box = TextBoxWidget:new{
        text = table.concat(lines, "\n"), face = face, width = tw, alignment = "left",
        fgcolor = fg, bgcolor = bg,
    }
    local h = box:getSize().h
    return CenterContainer:new{ dimen = Geom:new{ w = maxw, h = h }, box }, h
end

return MapText
