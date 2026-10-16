--[[--
宿主抽象。游戏代码只通过 host 对象访问外部世界：
  host:showScreen(view)        -- view = { title, lines = {string...}, buttons = { 按钮 | {按钮...}(一行) | { label }(分组标题) }, on_close?, map? = {等宽文本行} }；再次调用即刷新
  host:closeScreen()
  host:schedule(seconds, fn)   -- 返回句柄
  host:unschedule(handle)
  host:loadState() -> table|nil
  host:saveState(table)
  host:getSetting(key, default) / host:setSetting(key, value)
  host:notify(text)
可选 host:now() -> 秒（默认 os.time，测试注入虚拟时钟）。
新宿主只需实现这些方法，Interface.check 校验缺失项。
--]]
local Interface = {}

Interface.METHODS = {
    "showScreen", "closeScreen", "schedule", "unschedule",
    "loadState", "saveState", "getSetting", "setSetting", "notify",
}

function Interface.check(host)
    for _, m in ipairs(Interface.METHODS) do
        if type(host[m]) ~= "function" then
            error("adarkroom host missing method: " .. m)
        end
    end
    return host
end

return Interface
