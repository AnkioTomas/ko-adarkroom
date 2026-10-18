package.path = "adarkroom.koplugin/?.lua;" .. package.path
local T = require("adarkroom.i18n")
assert(T.candidates("zh_CN")[1] == nil and T.candidates("zh_TW")[1] == "zh_TW" and T.candidates("en_US")[1] == "en")
for _, lang in ipairs({ "en", "zh_TW" }) do
    local c = T.load(lang)
    local base = require("adarkroom.i18n.en")
    for k in pairs(base) do assert(c[k], lang .. " missing " .. k) end
end
T.load("en")
assert(T("已是最新版本（%s）", "1.0.0") == "Already up to date (1.0.0)")
print("OK i18n")
