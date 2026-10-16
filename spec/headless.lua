-- 无 KOReader 的冒烟测试：在仓库根目录运行 `lua spec/headless.lua`（Lua 5.1 / LuaJIT / 5.4）。
-- 宿主桩带虚拟时钟：advance(秒) 按到期顺序执行定时器。
package.path = "adarkroom.koplugin/?.lua;" .. package.path
math.randomseed(42)

local clock, seq, queue, saved, view = 0, 0, {}, nil, nil
local host = {
    showScreen = function(_, v) view = v end, closeScreen = function() view = nil end,
    schedule = function(_, s, fn) seq = seq + 1; queue[#queue + 1] = { at = clock + s, seq = seq, fn = fn } end,
    unschedule = function(_, fn) for i = #queue, 1, -1 do if queue[i].fn == fn then table.remove(queue, i) end end end,
    loadState = function() return saved end, saveState = function(_, t) saved = t end,
    getSetting = function(_, _, d) return d end, setSetting = function() end, notify = function() end,
    now = function() return clock end,
}
require("adarkroom.host.interface").check(host)

local function advance(secs)
    local stop = clock + secs
    while true do
        table.sort(queue, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.seq < b.seq end)
        local t = queue[1]
        if not t or t.at > stop then break end
        table.remove(queue, 1)
        clock = math.max(clock, t.at)
        t.fn()
    end
    clock = stop
end

local function flat()
    local out = {}
    for _, b in ipairs(view.buttons) do
        if b[1] then for _, c in ipairs(b) do out[#out + 1] = c end
        elseif b.text then out[#out + 1] = b end
    end
    return out
end
local function find(prefix)
    for _, b in ipairs(flat()) do
        if b.text:sub(1, #prefix) == prefix then return b end
    end
end
local function click(prefix)
    advance(0)
    local b = find(prefix)
    assert(b, "no button " .. prefix .. " in: " .. table.concat((function()
        local t = {} for _, x in ipairs(flat()) do t[#t + 1] = x.text end return t end)(), " / "))
    assert(b.enabled ~= false, "button disabled: " .. b.text)
    b.callback()
    advance(0)
end
-- 事件可能随时弹出；测试只关心主线，遇到事件就选最后一个按钮离开
local function dismissEvents(engine)
    local guard = 0
    while engine.events:activeEvent() and guard < 10 do
        advance(0)
        local bs = flat()
        bs[#bs].callback()
        guard = guard + 1
    end
    advance(0)
end

-- 1. 第 1 批存档迁移 -----------------------------------------------------------
saved = { fire = 2, wood = 7, log = { "旧日志" } }
local g = require("adarkroom.game").new(host):show()
local sm = g.engine.state
assert(sm:get("stores.wood") == 7 and sm:get("game.fire.value") == 2, "migrate")
g:close()

-- 2. 新游戏进程：火 → 建造者 → 森林 → 伐木 → 陷阱/小屋 → 工人收入 -----------------
saved, queue, clock = nil, {}, 0
g = require("adarkroom.game").new(host):show()
local engine = g.engine
sm = engine.state
advance(0)
assert(view.title == "小黑屋", view.title)
click("生火")
assert(sm:get("game.fire.value") == 3 and sm:get("game.builder.level") == 0)
assert(not find("添柴").enabled, "stoke on cooldown")
advance(10)
click("添柴")
-- 保持火旺，等建造者一路恢复（每 30 秒一阶，需要室温 >= warm）
for _ = 1, 20 do
    advance(30); dismissEvents(engine)
    if find("添柴") and find("添柴").enabled and (sm:get("stores.wood") or 1) > 0 then click("添柴") end
end
assert(engine.modules.outside, "forest unlocked")
print("builder level", sm:get("game.builder.level"), "wood", sm:get("stores.wood"))
-- 去屋外伐木
click("→ ")
assert(engine.activeModule.name == "outside")
for _ = 1, 30 do
    dismissEvents(engine)
    if find("伐木").enabled then click("伐木") end
    advance(60)
end
dismissEvents(engine)
print("wood after gathering", sm:get("stores.wood"))
-- 回屋里，建造者 level 3 -> 4 在回到房间时发生
for _, b in ipairs(flat()) do if b.text:find("^→ ") then b.callback() end end
advance(0); dismissEvents(engine)
assert(engine.activeModule.name == "room")
assert(sm:get("game.builder.level") == 4, "builder helping: " .. tostring(sm:get("game.builder.level")))
-- 建陷阱、小屋
if sm:get("game.fire.value") == 0 then click("生火") else advance(10) click("添柴") end
advance(120)
dismissEvents(engine)
click("陷阱")
assert(sm:get('game.buildings["trap"]') == 1, "trap built")
sm:set("stores.wood", 1000)
dismissEvents(engine)
click("小屋")
assert(sm:get('game.buildings["hut"]') == 1, "hut built")
-- 等人口到来，分配工人
for _ = 1, 10 do advance(60); dismissEvents(engine) if sm:get("game.population", true) > 0 then break end end
assert(sm:get("game.population", true) > 0, "population arrived")
local gatherIncome = sm:get('income["gatherer"]')
assert(gatherIncome and gatherIncome.stores.wood == sm:get("game.population"), "gatherer income")
sm:set("stores.fur", 100); sm:set("stores.meat", 100)
dismissEvents(engine)
click("小屋") -- 第二间（顺便测费用递增）
assert(sm:get('game.buildings["hut"]') == 2)
sm:set("stores.wood", 1000); dismissEvents(engine)
click("狩猎小屋")
assert(type(sm:get('game.workers["hunter"]')) == "number", "hunter job added")
click("→ ")
dismissEvents(engine)
click("+1")
assert(sm:get('game.workers["hunter"]') == 1, "assigned hunter")
local fur0 = sm:get("stores.fur")
advance(10); dismissEvents(engine)
assert(sm:get("stores.fur") > fur0 or sm:get("stores.fur") == fur0 + 0.5, "hunter income")
-- 查看陷阱
advance(90); dismissEvents(engine)
-- 「陷阱被毁」事件可能随机拆掉陷阱，补一个保证按钮存在
if sm:get('game.buildings["trap"]', true) == 0 then sm:set('game.buildings["trap"]', 1); advance(0) end
click("查看陷阱")

-- 3. 小偷剧情：开放世界后库存超 5000 -> 小偷收入 -> 全局事件
sm:set("features.location.world", true)
sm:set("stores.wood", 6000)
assert(sm:get("game.thieves") == 1 and sm:get('income["thieves"]'), "thieves started")

-- 4. 尘途与世界：罗盘 → 整理背包 → 出发 → 移动 → 战斗 → 拾取 → 中途关闭再继续 → 回家
sm:set("stores.compass", 1)
assert(engine.modules.path and engine.modules.world, "path opened by compass")
assert(type(sm:get("game.world.map")) == "table" and sm:get("game.world.map")[30][30] == "A", "map generated")
sm:set('stores["cured meat"]', 30); sm:set('stores["s armour"]', 1)
dismissEvents(engine)
engine:travelTo(engine.modules.path); advance(0); dismissEvents(engine)
click("+10")
assert(engine.modules.path:outfit()["cured meat"] == 10, "packed meat")
click("出发")
local world = engine.modules.world
assert(engine.activeModule == world and world.health == 45, "embarked, hp " .. tostring(world.health))
assert(sm:get('stores["cured meat"]') == 20, "meat taken from stores")
assert(view.map and #view.map == 15 and view.map[8]:sub(11, 11) == "@", "map viewport centered")
click("北")
assert(world.curPos[2] == 29, "moved north")
dismissEvents(engine)
-- 中途关闭、重开：继续远征
g:close()
assert(saved.expedition and saved.expedition.curPos[2] == 29, "expedition saved")
g = require("adarkroom.game").new(host):show()
engine, sm = g.engine, g.engine.state
world = engine.modules.world
advance(0)
assert(engine.activeModule == world and world.curPos[2] == 29, "expedition resumed")
-- 战斗：咆哮的野兽
engine.events:startEvent(require("adarkroom.events.encounters")[1])
advance(0)
local rounds = 0
while engine.events.fight and rounds < 60 do
    local b = find("挥拳")
    if b and b.enabled then b.callback() end
    advance(1)
    rounds = rounds + 1
end
assert(world.health > 0 and engine.events:activeEvent(), "won the fight")
print("fight rounds", rounds, "hp", world.health)
advance(1)
local te = find("拿走一切")
if te and te.enabled then te.callback() advance(0) end
click("离开")
advance(1)
assert(engine.events:activeEvent() == nil, "left fight")
-- 每个地标事件随机走一遍，抓转换后的运行时错误（血量、补给开挂，避免死亡）
local names = {}
for k in pairs(require("adarkroom.events.setpieces")) do names[#names + 1] = k end
table.sort(names)
for _, name in ipairs(names) do
    for _ = 1, 3 do
        local o = engine.modules.path:outfit()
        o.torch, o["cured meat"], o.medicine = 10, 10, 5
        world.health, world.water = 999, 10
        engine.events:startEvent(engine.events:setpiece(name))
        local steps = 0
        while engine.events:activeEvent() and steps < 80 do
            advance(0)
            if engine.events.fight then
                local b = find("挥拳") or flat()[1]
                if b and b.enabled ~= false then b.callback() end
                world.health = 999
                advance(1)
            else
                local opts = {}
                for _, b in ipairs(flat()) do if b.enabled ~= false then opts[#opts + 1] = b end end
                if #opts == 0 then advance(1) else opts[math.random(#opts)].callback() end
                advance(1)
            end
            steps = steps + 1
        end
        if engine.events:activeEvent() then engine.events:endEvent() end
    end
end
world.curPos = { 30, 29 }
world.health = world:getMaxHealth()
print("setpieces exercised", #names)

-- 走回村庄
click("南")
dismissEvents(engine)
assert(engine.activeModule == engine.modules.path, "returned home: " .. tostring(engine.activeModule.name))
assert(sm:get("expedition") == nil, "expedition cleared")
assert(sm:get('stores["cured meat"]') >= 20, "outfit returned")

-- 5. 存盘与关闭
g:close()
assert(saved.port_version == 2 and #queue == 0, "close clears timers")
print("OK", "pop", saved.game.population, "huts", saved.game.buildings.hut)
