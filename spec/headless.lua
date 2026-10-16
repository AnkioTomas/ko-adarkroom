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
    getSetting = function(_, k, d) if k == "page_rows" then return 100 end return d end,
    setSetting = function() end, notify = function() end,
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


-- 6. 残破战舰（Executioner）全部事件随机走，带状态 / 特技 / 自爆 / atHealth --------------
local World = require("adarkroom.world")
local exe = require("adarkroom.events.executioner")
local enames = {}
for k in pairs(exe) do enames[#enames + 1] = k end
table.sort(enames)
sm:set('stores["kinetic armour"]', 1)
for _, name in ipairs(enames) do
    for _ = 1, 4 do
        world.state = world.state or World.deepcopy(sm:get("game.world"))
        local o = engine.modules.path:outfit()
        o.torch, o["cured meat"], o.medicine, o.hypo, o.stim = 10, 10, 5, 3, 1
        o["plasma rifle"], o["energy cell"] = 1, 50
        world.health, world.water = 999, 10
        engine.events:startEvent(exe[name])
        local steps = 0
        while engine.events:activeEvent() and steps < 300 do
            advance(0)
            if engine.events.fight then
                local bs = {}
                for _, b in ipairs(flat()) do if b.enabled ~= false then bs[#bs + 1] = b end end
                if #bs > 0 then bs[math.random(#bs)].callback() end
                if world.health < 300 then world:setHp(999) end
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
        if world.dead then -- 不应发生（血量开挂），保险
            error("died in " .. name)
        end
    end
end
assert(engine.events.fight == nil)
-- 直接打每个带特技 / atHealth / 自爆的战斗场景，保证状态逻辑都跑到
local special = 0
for _, name in ipairs(enames) do
    local snames = {}
    for sn in pairs(exe[name].scenes) do snames[#snames + 1] = sn end
    table.sort(snames)
    for _, sn in ipairs(snames) do
        local sc = exe[name].scenes[sn]
        if sc.combat and (sc.specials or sc.atHealth or sc.explosion) then
            special = special + 1
            local o = engine.modules.path:outfit()
            o.stim, o["energy cell"], o["plasma rifle"] = 1, 200, 1
            world:setHp(999)
            engine.events:startEvent{ title = "S", scenes = { start = sc, ["end"] = { text = {}, buttons = {} } } }
            local t = 0
            while engine.events.fight and t < 120 do
                advance(0)
                local b = find("瓦解") or find("挥拳")
                if b and b.enabled ~= false and t > 20 then b.callback() end
                local sh = find("护盾")
                if sh and sh.enabled ~= false then sh.callback() end
                if world.health < 300 then world:setHp(999) end
                advance(1)
                t = t + 1
            end
            assert(not engine.events.fight, "special fight ended: " .. name .. "/" .. sn)
            if engine.events:activeEvent() then engine.events:endEvent() end
        end
    end
end
assert(special >= 5, "special scenes " .. special)
print("executioner events exercised", #enames, "special fights", special)

-- 7. 背包满时的丢弃菜单 --------------------------------------------------------------
do
    local o = engine.modules.path:outfit()
    for k in pairs(o) do o[k] = nil end
    o["cured meat"] = engine.modules.path:getCapacity()
    engine.events:startEvent{ title = "T", scenes = { start = { text = { "x" }, loot = { iron = { min = 3, max = 3, chance = 1 } },
        buttons = { { id = "leave", text = "离开", nextScene = "end" } } } } }
    advance(0)
    click("铁")
    assert(engine.events:activeEvent().dropFor, "drop menu opened")
    assert(view.title == "T" and find("熏肉 x1"), "drop option")
    click("熏肉 x1")
    assert(o.iron == 1 and o["cured meat"] == engine.modules.path:getCapacity() - 1, "dropped and took")
    local row
    for _, r in ipairs(engine.events:activeEvent().loot) do if r.name == "cured meat" then row = r end end
    assert(row and row.left == 1, "dropped item back in loot")
    click("离开")
end

-- 8. 回家：战舰 + 星舰 + 蓝图 → 制造机 / 星舰模块 ------------------------------------
world.state = world.state or World.deepcopy(sm:get("game.world"))
world.state.executioner, world.state.ship = true, true
engine.modules.path:outfit()["plasma rifle blueprint"] = 1
world.curPos = { 30, 30 }
world:goHome()
advance(0)
assert(engine.modules.fabricator and engine.modules.ship, "fabricator + ship registered")
assert(sm:get('character.blueprints["plasma rifle"]'), "blueprint redeemed")
sm:set('stores["alien alloy"]', 30)
engine:travelTo(engine.modules.fabricator)
advance(0)
click("等离子步枪")
assert(sm:get('stores["plasma rifle"]') >= 1 and sm:get('stores["alien alloy"]') == 29, "fabricated")
click("液体循环器")
assert(not find("液体循环器").enabled, "max 1")

-- 9. 星舰 → 太空 → 结局 → 声望重开 ----------------------------------------------------
engine:travelTo(engine.modules.ship)
advance(0)
assert(not find("点火起飞").enabled, "no hull, no liftoff")
click("加固船身")
assert(find("点火起飞").enabled)
click("点火起飞")
assert(view.title == "准备好要离开了吗?", view.title)
click("裹足徘徊")
assert(find("点火起飞").enabled, "linger clears cooldown")
click("点火起飞")
click("点火起飞") -- 事件里的起飞
advance(0)
local space = engine.modules.space
assert(engine.activeModule == space and view.map, "in space")
-- 船身 1：不躲，迟早坠毁
local turns = 0
while engine.activeModule == space and turns < 200 do click("·") turns = turns + 1 end
assert(engine.activeModule == engine.modules.ship, "crashed back to ship after " .. turns)
assert(not find("点火起飞").enabled, "liftoff cooldown after crash")
for _ = 1, 39 do click("加固船身") end
advance(130)
sm:set('stores["fleet beacon"]', 1)
click("点火起飞")
advance(0)
assert(engine.activeModule == space)
-- 每回合挑不会撞的方向
turns = 0
while not space.ending and turns < 200 do
    local best
    for _, d in ipairs({ 0, -1, 1 }) do
        local nx = math.max(1, math.min(space.WIDTH, space.x + d))
        local safe = true
        for _, a in ipairs(space.asteroids) do
            if a.x == nx and a.y + a.speed >= space.HEIGHT then safe = false end
        end
        if safe and not best then best = d end
    end
    click(({ [0] = "·", [-1] = "←", [1] = "→" })[best or 0])
    turns = turns + 1
end
assert(space.ending, "reached the ending")
print("ascent turns", turns, "hull left", space.hull, "of", space.maxHull)
assert(view.lines[1]:find("信标"), "beacon ending text")
click("等待")
assert(view.lines[1]:find("游戏得分"), view.lines[1])
assert(saved.previous and saved.previous.score > 0 and saved.game == nil, "save wiped, prestige kept")
local total = saved.previous.score
click("重启")
engine = g.engine
sm = engine.state
advance(0)
assert(view.title == "小黑屋" and sm:get("previous.score") == total, "restarted with prestige")
assert(sm:get("stores.wood") == nil, "fresh stores")
-- 新世界里有被毁村落（cache），进去拿回声望库存
local W2 = require("adarkroom.world").new(engine)
assert(W2.LANDMARKS[W2.TILE and W2.TILE.CACHE or "U"], "cache landmark present")
local prevWood = sm:get("previous.stores")[1]
engine:prestigeCollect()
assert(sm:get("stores.wood", true) == prevWood and #sm:get("previous.stores") == 0, "prestige collected")
print("prestige total", total, "wood back", prevWood)

-- 10. 按钮分页 ------------------------------------------------------------------------
do
    local items = {}
    for i = 1, 30 do items[#items + 1] = { text = "b" .. i, callback = function() end } end
    host.getSetting = function(_, k, d) if k == "page_rows" then return 4 end return d end
    local rows = engine:paginate("k", items)
    assert(#rows == 5 and rows[5].pager and rows[5].pager.pages == 4, "paged")
    rows[5][3].callback(); advance(0)
    rows = engine:paginate("k", items)
    assert(rows[1][1].text == "b9" and rows[5].pager.page == 2, "next page")
    host.getSetting = function(_, k, d) if k == "page_rows" then return 100 end return d end
end

-- 5. 存盘与关闭
g:close()
assert(saved.port_version == 2 and #queue == 0, "close clears timers")
print("OK game", "prestige", saved.previous.score)

-- 11. 月读宿主模拟：utils.settings 桩 + UIManager 桩 -----------------------------------
do
    local files = {}
    package.loaded["utils.settings"] = {
        getSource = function(id) files[id] = files[id] or {} return files[id] end,
        saveSource = function(id, values) if values and values ~= files[id] then files[id] = values end files.flushed = (files.flushed or 0) + 1 end,
    }
    local shown
    package.loaded["ui/uimanager"] = {
        show = function(_, w) shown = w end, close = function() end,
        scheduleIn = function(_, s, fn) host:schedule(s, fn) end, unschedule = function(_, fn) host:unschedule(fn) end,
    }
    package.loaded["adarkroom.ui.screen"] = { open = function(v, oc) return { generic = true, view = v, on_close = oc } end }
    local MoonHost = require("adarkroom.host.moon")
    local mh = MoonHost.new()
    mh.now = function() return clock end
    queue, clock = {}, 0
    local mg = require("adarkroom.game").new(mh):show()
    advance(0)
    assert(shown and shown.generic and shown.view.title == "小黑屋", "fallback to generic screen without moon themes")
    mg.engine.state:set("stores.wood", 123)
    mg:close()
    assert(files["ext.adarkroom"].state.stores.wood == 123 and files.flushed > 0, "saved via utils.settings")
    mh:setSetting("page_rows", 6)
    assert(mh:getSetting("page_rows", 8) == 6 and files["ext.adarkroom"].settings.page_rows == 6)
    -- 有月读主题界面时优先用它
    package.loaded["adarkroom.ui.moon_screen"] = { open = function(v) return { moon = true, view = v } end }
    local mh2 = MoonHost.new()
    mh2.now = function() return clock end
    local mg2 = require("adarkroom.game").new(mh2):show()
    advance(0)
    assert(shown.moon and mg2.engine.state:get("stores.wood") == 123, "moon screen used, save reloaded")
    mg2:close()
    -- moon_source 描述文件符合 registry 约定
    package.loaded["gettext"] = function(s) return s end
    local desc = dofile("adarkroom.koplugin/moon_source.lua")
    assert(desc.api == 1 and desc.id:match("^ext%.[%w_%-]+$") and desc.provides.source == false)
    assert(desc.provides.home_widgets[1].id == "entry" and type(desc.provides.home_widgets[1].build) == "function")
    print("OK moon host")
end
