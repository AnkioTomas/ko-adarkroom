--[[--
第 1 批最小可玩：黑屋子 + 生火/添柴，验证宿主接线与存档。
完整引擎（state manager、事件、建筑）在第 2、3 批替换本文件的逻辑。
--]]
local _ = require("gettext")

local FIRE = { _("熄灭"), _("闷烧"), _("燃烧"), _("旺盛"), _("熊熊") }
local FIRE_DECAY = 300 -- 秒（原版 Room._FIRE_COOL_DELAY = 5 分钟）

local Game = {}
Game.__index = Game

function Game.new(host)
    local self = setmetatable({ host = host }, Game)
    self.state = host:loadState() or { fire = 0, wood = 5, log = { _("屋子很冷。") } }
    return self
end

function Game:log(msg)
    local l = self.state.log
    table.insert(l, 1, msg)
    while #l > 8 do table.remove(l) end
end

function Game:save() self.host:saveState(self.state) end

function Game:stoke()
    local s = self.state
    if s.wood <= 0 then self:log(_("木头用完了。")) return self:render() end
    s.wood = s.wood - 1
    if s.fire == 0 then self:log(_("火点着了。")) end
    s.fire = math.min(s.fire + 1, #FIRE - 1)
    self:log(_("火") .. FIRE[s.fire + 1] .. "。")
    self:armCooling()
    self:save()
    self:render()
end

function Game:armCooling()
    if self.cool then self.host:unschedule(self.cool) end
    self.cool = function()
        self.cool = nil
        local s = self.state
        if s.fire > 0 then
            s.fire = s.fire - 1
            self:log(_("火") .. FIRE[s.fire + 1] .. "。")
            self:save()
            if self.visible then self:render() end
            if s.fire > 0 then self:armCooling() end
        end
    end
    self.host:schedule(FIRE_DECAY, self.cool)
end

function Game:render()
    local s = self.state
    local lines = {
        s.fire == 0 and _("一间黑屋子") or _("一间生着火的屋子"), "",
        _("火：") .. FIRE[s.fire + 1], _("木头：") .. s.wood, "",
    }
    for _, m in ipairs(s.log) do lines[#lines + 1] = m end
    self.visible = true
    self.host:showScreen{
        title = _("小黑屋"),
        lines = lines,
        buttons = {
            { text = s.fire == 0 and _("生火") or _("添柴"), enabled = s.wood > 0, callback = function() self:stoke() end },
            { text = _("退出"), callback = function() self:close() end },
        },
    }
end

function Game:close()
    self.visible = false
    if self.cool then self.host:unschedule(self.cool) self.cool = nil end
    self:save()
    self.host:closeScreen()
end

function Game:show()
    if self.state.fire > 0 then self:armCooling() end
    self:render()
    return self
end

return Game
