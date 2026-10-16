-- 第二组无 KOReader 测试：各阶段存档/关闭/重开、屋内屋外全局事件逐选项、死亡、分页设置、关闭后无定时器。
-- 在仓库根目录运行 `lua spec/headless2.lua`。
local H = dofile("spec/harness.lua")
math.randomseed(7)

local RICH = { wood = 5000, fur = 5000, meat = 5000, scales = 500, teeth = 500, cloth = 500, leather = 500,
    iron = 500, coal = 500, steel = 500, sulphur = 500, bait = 100, ["cured meat"] = 500, medicine = 50,
    bullets = 100, ["energy cell"] = 50, torch = 50, charm = 5, ["alien alloy"] = 20, compass = 1 }

-- A. 各阶段关闭再打开 -------------------------------------------------------------
H.saved = nil
local g, e = H.open()
e.state:set("game.fire.value", 3)
e:startCooldown("stoke", 10)
H.closeCheck(g)
g, e = H.open()
assert(e.state:get("game.fire.value") >= 2, "fire kept")
assert(e.activeModule.name == "room")
-- 屋外
e.state:set("features.location.outside", true)
e.state:setM("stores", RICH)
e.state:set("game.builder.level", 4)
H.closeCheck(g)
g, e = H.open()
assert(e.modules.outside, "outside restored")
H.click("→ ")
-- 漫漫尘途
H.closeCheck(g)
g, e = H.open()
assert(e.modules.path, "path restored (compass)")
e:travelTo(e.modules.path)
H.advance(0)
H.click("+10")
H.click("出发")
H.click("北")
H.click("北")
local w = e.modules.world
local pos, water = { w.curPos[1], w.curPos[2] }, w.water
H.closeCheck(g)
assert(H.saved.expedition, "expedition saved")
g, e = H.open()
w = e.modules.world
assert(e.activeModule == w and w.curPos[1] == pos[1] and w.curPos[2] == pos[2] and w.water == water, "expedition resumed")
assert(H.view.map, "map shown after resume")
-- 远征中战斗时关闭：重开回到地图（事件不保存）
e.events:triggerFight()
H.advance(0)
assert(e.events.fight, "fight started")
H.closeCheck(g)
g, e = H.open()
assert(e.activeModule == e.modules.world and not e.events.fight, "fight dropped, map resumed")

-- B. 死亡 --------------------------------------------------------------------------
w = e.modules.world
w:setHp(1)
e.events:startEvent(require("adarkroom.events.encounters")[1])
for _ = 1, 30 do H.advance(1) end
assert(w.dead or e.activeModule == e.modules.room, "died")
H.advance(3)
assert(e.activeModule == e.modules.room, "back in room after death")
assert(e.state:get("outfit") == nil and e.state:get("expedition") == nil, "outfit lost")
assert(e:cooldownLeft("embark") > 0, "embark cooldown after death")

-- B2. 所有带战斗的场景（含行刑者/战舰类特技）：特技触发、胜利、阵亡后不残留定时器 -----
do
    local w2 = e.modules.world
    local scenes = {}
    local function collect(list)
        for _, ev in pairs(list) do
            for _, sc in pairs(ev.scenes or {}) do if sc.combat then local c = {} for k, v in pairs(sc) do c[k] = v end c.onLoad = nil
                if c.specials then local sp = {} for j, s in ipairs(c.specials) do local a = s.action sp[j] = { delay = s.delay, action = function(...) SPECIALS = (SPECIALS or 0) + 1 return a(...) end } end c.specials = sp end
                scenes[#scenes + 1] = c end end
        end
    end
    collect(require("adarkroom.events.encounters"))
    collect(require("adarkroom.events.setpieces"))
    collect(require("adarkroom.events.executioner"))
    local nspecial, nwin, ndeath = 0, 0, 0
    for i, sc in ipairs(scenes) do
        local before = #H.queue
        w2.dead = false
        local win = i % 2 == 0 or sc.specials ~= nil
        if win then sc.hit = 0 end
        w2:setHp(win and 100000 or 1)
        e.events:startEvent({ title = "t", scenes = { start = sc } })
        H.advance(0)
        assert(e.events.fight, "fight " .. i)
        if sc.specials then for _ = 1, 30 do if win then w2:setHp(w2:getMaxHealth()) end H.advance(1) end end
        local n = 0
        while e.events.fight and n < 2000 do
            local f = e.events.fight
            if win then w2:setHp(w2:getMaxHealth()) f.enemyHp = 1 e.events:useWeapon("fists") end
            H.advance(1) n = n + 1
        end
        assert(not e.events.fight, "fight did not end " .. i)
        if win and not w2.dead then
            nwin = nwin + 1
            H.advance(0)
            assert(e.events:activeEvent(), "loot screen " .. i .. " " .. tostring(sc.enemy) .. " hp " .. w2.health .. " dead " .. tostring(w2.dead) .. " mod " .. e.activeModule.name)
            e.events:endEvent()
        else
            ndeath = ndeath + 1
            H.advance(5)
        end
        H.advance(0)
        e.events.stack = {}
        e:travelTo(e.modules.room)
    end
    print(("combat scenes %d specials fired %d wins %d deaths %d"):format(#scenes, SPECIALS or 0, nwin, ndeath))
    assert((SPECIALS or 0) > 0, "no special fired")
end
H.closeCheck(g)
g, e = H.open()
assert(e.activeModule == e.modules.room and e.modules.world == nil or e.activeModule == e.modules.room, "dead save reopens in room")

-- C. 屋内 / 屋外 / 全局事件：每个事件反复随机选项走到底 ----------------------------
local pools = {}
for _, mod in ipairs({ "global", "room", "outside" }) do
    for _, ev in ipairs(require("adarkroom.events." .. mod)) do pools[#pools + 1] = { mod = mod, ev = ev } end
end
e.state:set("game.buildings[\"hut\"]", 10)
e.state:set("game.population", 40)
e.state:set("game.buildings[\"trap\"]", 5)
e.state:set("game.buildings[\"trading post\"]", 1)
e.state:set("game.buildings[\"workshop\"]", 1)
e.state:set("game.thieves", 1)
e.state:set("game.stolen", { wood = 10 })
local fired, choices = 0, 0
for _, p in ipairs(pools) do
    local where = p.mod == "outside" and e.modules.outside or e.modules.room
    for _ = 1, 12 do
        e.state:setM("stores", RICH)
        e:travelTo(where)
        H.advance(0)
        e.events:startEvent(p.ev)
        fired = fired + 1
        local steps = 0
        while e.events:activeEvent() and steps < 30 do
            H.advance(0)
            local opts = {}
            for _, b in ipairs(H.flat()) do if b.enabled ~= false then opts[#opts + 1] = b end end
            if #opts == 0 then H.advance(1) else opts[math.random(#opts)].callback() choices = choices + 1 end
            H.advance(1)
            steps = steps + 1
        end
        if e.events:activeEvent() then e.events:endEvent() end
    end
end
-- 延迟事件（神秘流浪者 60 秒回来）跑完
H.advance(120)
print("village events", #pools, "runs", fired, "choices", choices)

-- D. page_rows 设置 -------------------------------------------------------------------
local items = {}
for i = 1, 20 do items[#items + 1] = { text = "b" .. i, callback = function() end } end
for _, case in ipairs({ { 3, 5 }, { "bad", 2 }, { 1, 2 }, { 100, 10 } }) do
    H.settings.page_rows = case[1]
    local rows = e:paginate("pr" .. tostring(case[1]), items)
    local pager = rows[#rows].pager
    local pages = pager and pager.pages or 1
    -- 3 行/页 → 10 对按钮分 4 页；无效值回落默认 8 → 2 页；100 → 1 页
    local want = ({ [3] = 4, bad = 2, [1] = 2, [100] = 1 })[case[1]]
    assert(pages == want, "page_rows " .. tostring(case[1]) .. " pages " .. pages)
end
H.settings.page_rows = nil

-- E. 通知日志上限与渲染 -------------------------------------------------------------
while e.events:activeEvent() do e.events:endEvent() end -- 随机事件弹窗时不显示日志
for i = 1, 50 do e:notify(nil, "msg" .. i) end
H.advance(0)
local n = 0
for _, l in ipairs(H.view.lines) do if l:match("^msg") then n = n + 1 end end
assert(n > 0 and n <= 20, "log capped: " .. n)

-- F. 星舰阶段关闭重开；通关后关闭重开只剩声望 ----------------------------------------
e.state:setM("stores", RICH)
e:module("ship")
e:module("fabricator")
H.closeCheck(g)
g, e = H.open()
assert(e.modules.ship and e.modules.fabricator, "ship + fabricator restored")
e:travelTo(e.modules.ship)
H.click("加固船身")
e.state:set("game.spaceShip.seenWarning", true)
H.click("点火起飞")
assert(e.activeModule.name == "space")
H.closeCheck(g) -- 太空中关闭
g, e = H.open()
assert(e.activeModule.name == "room" and e.modules.ship, "space not persisted, back in room")
e:travelTo(e.modules.ship)
H.advance(0)
e.state:set("game.spaceShip.hull", 200)
e:clearCooldown("liftoff")
H.click("点火起飞")
local sp = e.modules.space
while not sp.ending do sp:turn(0) end
H.advance(0)
for _, l in ipairs(H.view.lines) do assert(l ~= "────────", "ending shows no log") end
assert(H.find("重启") and not H.find("→ "), "ending: restart, no travel")
H.closeCheck(g) -- 结局界面直接关闭
assert(H.saved.game == nil and H.saved.previous.score > 0, "closed at ending: prestige only")
g, e = H.open()
assert(e.state:get("previous.score") > 0 and e.state:get("stores.wood") == nil, "new game with prestige")
H.closeCheck(g)
print("OK headless2")

-- G. 月读首页卡片摘要 ---------------------------------------------------------------
do
    local Card = require("adarkroom.ui.moon_card")
    local s = Card.summary(nil)
    assert(s.new_game and s.title == "小黑屋" and s.line1 ~= "", "card: new game")
    s = Card.summary({ previous = { score = 42 } })
    assert(s.new_game and s.line2:find("42"), "card: prestige only")
    s = Card.summary({ game = { builder = { level = 4 }, fire = { value = 3 }, buildings = { hut = 3 }, population = 9 },
        stores = { wood = 123.4 }, features = { location = { outside = true } } })
    assert(not s.new_game and s.line1 == "火堆燃烧着 · 小型村落" and s.line2 == "木头 123 · 人口 9/12", "card: " .. s.line1 .. " | " .. s.line2)
    s = Card.summary({ game = { fire = { value = 1 }, builder = { level = 0 } }, stores = {} })
    assert(s.line1:find("小黑屋") and s.line2 == "木头 0", "card: dark room")
    print("OK card")
end
