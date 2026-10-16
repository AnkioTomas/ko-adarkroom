-- 无 KOReader 的冒烟测试：lua spec/headless.lua（在仓库根目录运行）
package.path = "adarkroom.koplugin/?.lua;" .. package.path
local queue, saved = {}, nil
local host = {
    showScreen = function(_, v) _G.last_view = v end, closeScreen = function() end,
    schedule = function(_, s, fn) queue[#queue + 1] = { s = s, fn = fn } end,
    unschedule = function(_, fn) for i = #queue, 1, -1 do if queue[i].fn == fn then table.remove(queue, i) end end end,
    loadState = function() return saved end, saveState = function(_, t) saved = t end,
    getSetting = function(_, _, d) return d end, setSetting = function() end, notify = function() end,
}
require("adarkroom.host.interface").check(host)
local function run(maxs) -- 执行一轮当前已排队且 <= maxs 秒的定时器（含其中新排的 0 秒刷新）
    for _ = 1, 3 do
        local snap = queue
        queue = {}
        for _, t in ipairs(snap) do
            if t.s <= maxs then t.fn() else queue[#queue + 1] = t end
        end
        maxs = 0
    end
end
local function btn(text)
    for _, b in ipairs(last_view.buttons) do if b.text == text then return b.callback() end end
    error("no button " .. text)
end
-- 1. 第 1 批存档迁移
saved = { fire = 2, wood = 7, log = { "旧日志" } }
local g = require("adarkroom.game").new(host):show()
local sm = g.engine.state
assert(sm:get("stores.wood") == 7 and sm:get("game.fire.value") == 2, "migrate")
run(1)
assert(last_view.title == "小黑屋" or last_view.title == "生火的屋子" or last_view.title, "title")
print("title:", last_view.title); print(table.concat(last_view.lines, " | "))
btn("添柴"); run(1)
assert(sm:get("game.fire.value") == 3 and sm:get("stores.wood") == 6)
-- 2. 收入
sm:setIncome("gatherer", { delay = 2, stores = { wood = 3 } }); run(1); run(1); run(1)
assert(sm:get("stores.wood") >= 9, "income " .. tostring(sm:get("stores.wood")))
-- 3. 事件
sm:set("game.thieves", 1); sm:set("game.stolen", { wood = 4 })
g.engine.events:triggerEvent(); run(0)
print("event:", last_view.title, last_view.buttons[1].text)
btn("绞死他"); run(0); btn(last_view.buttons[1].text); run(0)
assert(sm:get("game.thieves") == 2 and g.engine.events:activeEvent() == nil)
-- 4. 存盘与关闭
g:close(); assert(saved.port_version == 2 and #queue == 0, "close clears timers")
print("OK", sm:get("stores.wood"))
