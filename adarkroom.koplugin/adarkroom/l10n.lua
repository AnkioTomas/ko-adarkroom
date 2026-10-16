-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
-- Port of A Dark Room script/localization.js (doublespeakgames/adarkroom).
--[[--
本地化：key 是原版英文串，表来自上游 lang/<locale>/strings.js（tools/gen_l10n.py 生成）。
L(str, ...) 翻译并替换 {0} {1}…；找不到翻译就用英文原文。
--]]
local L10n = { locale = "zh_cn", table = {} }

function L10n.load(locale)
    L10n.locale = locale or "zh_cn"
    if L10n.locale == "en" then L10n.table = {} return end
    local ok, t = pcall(require, "adarkroom.l10n." .. L10n.locale)
    L10n.table = ok and type(t) == "table" and t or {}
end

function L10n.translate(str, ...)
    if str == nil then return nil end
    local s = L10n.table[str] or str
    local args = { ... }
    if #args > 0 then
        s = s:gsub("{(%d+)}", function(i)
            local v = args[tonumber(i) + 1]
            if v == nil then return "{" .. i .. "}" end
            return tostring(v)
        end)
    end
    return s
end

setmetatable(L10n, { __call = function(_, ...) return L10n.translate(...) end })

return L10n
