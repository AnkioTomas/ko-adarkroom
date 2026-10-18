-- 离线测试入口：lua spec/run.lua（在仓库根目录运行）
for _, f in ipairs({ "spec/headless.lua", "spec/headless2.lua", "spec/i18n.lua" }) do
    dofile(f)
end
