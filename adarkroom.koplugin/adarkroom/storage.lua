-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
--[[--
存档位置：<KOReader 数据目录>/.moon/game/adarkroom/save.lua（存档 + KOReader 宿主的设置 setting_*）。
KOReader 与月读两种宿主共用同一份存档。

第一次打开新位置时从旧位置迁移（只复制，不删旧文件，旧的留作备份）：
  旧 KOReader 存档 settings/adarkroom.lua、旧月读存档 utils.settings 的 ext.adarkroom.state。
两边都有存档时取进度多的那份（库存总量）。新文件写好并 flush 后才算迁移完成。
--]]
local M = {}

-- 可注入（测试用）
M.deps = {
    dataDir = function() return require("datastorage"):getDataDir() end,
    settingsDir = function() return require("datastorage"):getSettingsDir() end,
    open = function(path) return require("luasettings"):open(path) end,
    exists = function(path) local f = io.open(path, "rb") if f then f:close() return true end return false end,
    mkdirp = function(path)
        local ok, util = pcall(require, "util")
        if ok and util and util.makePath then util.makePath(path) return end
        local lfs = require("libs/libkoreader-lfs")
        local cur = ""
        for part in path:gmatch("[^/]+") do
            cur = cur .. "/" .. part
            if not lfs.attributes(cur, "mode") then lfs.mkdir(cur) end
        end
    end,
    moonState = function()
        local ok, S = pcall(require, "utils.settings")
        if ok and type(S) == "table" and S.getSource then
            local c = S.getSource("ext.adarkroom")
            return c and c.state
        end
    end,
}

function M.dir() return M.deps.dataDir() .. "/.moon/game/adarkroom" end

local function score(st)
    if type(st) ~= "table" then return -1 end
    local n = 0
    if type(st.stores) == "table" then
        for _, v in pairs(st.stores) do n = n + (tonumber(v) or 0) end
    end
    return n
end

local store

function M.open()
    if store then return store end
    local d = M.deps
    local dir = M.dir()
    d.mkdirp(dir)
    local path = dir .. "/save.lua"
    local fresh = not d.exists(path)
    local s = d.open(path)
    if fresh then
        local from = {}
        local old_path = d.settingsDir() .. "/adarkroom.lua"
        if d.exists(old_path) then
            local old = d.open(old_path)
            for k, v in pairs(old.data or {}) do s:saveSetting(k, v) end
            from[#from + 1] = old_path
        end
        local ms = d.moonState()
        if ms and score(ms) > score(s:readSetting("state")) then
            s:saveSetting("state", ms)
            from[#from + 1] = "moon:ext.adarkroom.state"
        end
        if #from > 0 then s:saveSetting("migrated_from", table.concat(from, ", ")) end
        s:flush()
    end
    store = s
    return s
end

function M._reset() store = nil end

return M
