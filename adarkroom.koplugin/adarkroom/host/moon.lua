--[[--
月读宿主适配（第 1 批为桩）。月读扩展契约只提供首页组件（provides.home_widgets），
没有独立的界面/定时 API，因此游戏界面仍走 KOReader UIManager；存档与设置改用
utils.settings.getSource("ext.adarkroom")（settings/ext.adarkroom.lua），不写月读自己的分区。
--]]
local KOHost = require("adarkroom.host.koreader")
local Interface = require("adarkroom.host.interface")

local ID = "ext.adarkroom"

local Host = setmetatable({}, { __index = KOHost })
Host.__index = Host
Host.ID = ID

function Host.new(opts)
    local self = setmetatable({ opts = opts or {} }, Host)
    return Interface.check(self)
end

local function conf() return require("utils.settings").getSource(ID) end
local function save() require("utils.settings").saveSource(ID) end

function Host:loadState() return conf().state end
function Host:saveState(state) conf().state = state; save() end

function Host:getSetting(key, default)
    local v = (conf().settings or {})[key]
    if v == nil then return default end
    return v
end

function Host:setSetting(key, value)
    local c = conf()
    c.settings = c.settings or {}
    c.settings[key] = value
    save()
end

return Host
