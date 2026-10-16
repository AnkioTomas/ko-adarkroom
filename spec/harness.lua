-- 无 KOReader 测试用宿主桩（虚拟时钟），供 spec/headless2.lua 等使用。
package.path = "adarkroom.koplugin/?.lua;" .. package.path
local H = { clock = 0, seq = 0, queue = {}, saved = nil, view = nil, settings = {}, shows = 0 }
H.host = {
    showScreen = function(_, v) H.view = v H.shows = H.shows + 1 end,
    closeScreen = function() H.view = nil end,
    schedule = function(_, s, fn) H.seq = H.seq + 1; H.queue[#H.queue + 1] = { at = H.clock + s, seq = H.seq, fn = fn } end,
    unschedule = function(_, fn) for i = #H.queue, 1, -1 do if H.queue[i].fn == fn then table.remove(H.queue, i) end end end,
    loadState = function() return H.saved end, saveState = function(_, t) H.saved = t end,
    getSetting = function(_, k, d) local v = H.settings[k] if v == nil then return d end return v end,
    setSetting = function(_, k, v) H.settings[k] = v end, notify = function() end,
    now = function() return H.clock end,
}
require("adarkroom.host.interface").check(H.host)

function H.advance(secs)
    local stop = H.clock + secs
    while true do
        table.sort(H.queue, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.seq < b.seq end)
        local t = H.queue[1]
        if not t or t.at > stop then break end
        table.remove(H.queue, 1)
        H.clock = math.max(H.clock, t.at)
        t.fn()
    end
    H.clock = stop
end

function H.flat()
    local out = {}
    for _, b in ipairs(H.view and H.view.buttons or {}) do
        if b[1] then for _, c in ipairs(b) do out[#out + 1] = c end
        elseif b.text then out[#out + 1] = b end
    end
    return out
end
function H.find(prefix)
    for _, b in ipairs(H.flat()) do if b.text:sub(1, #prefix) == prefix then return b end end
end
function H.click(prefix)
    H.advance(0)
    local b = H.find(prefix)
    local t = {} for _, x in ipairs(H.flat()) do t[#t + 1] = x.text end
    assert(b, "no button " .. prefix .. " in: " .. table.concat(t, " / "))
    assert(b.enabled ~= false, "button disabled: " .. b.text)
    b.callback()
    H.advance(0)
end
function H.open()
    local g = require("adarkroom.game").new(H.host):show()
    H.advance(0)
    return g, g.engine
end
--- 关闭后不应再有定时器，也不应再刷新界面
function H.closeCheck(g)
    g:close()
    assert(#H.queue == 0, "timers left after close: " .. #H.queue)
    local n = H.shows
    H.advance(600)
    assert(H.shows == n, "render after close")
end
return H
