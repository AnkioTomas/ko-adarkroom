# ko-a-dark-room · 小黑屋 KOReader 插件

把 [A Dark Room](https://github.com/doublespeakgames/adarkroom)（Michael Townsend / doublespeakgames，MPL-2.0）移植为 Lua 实现的 KOReader 插件，同时可作为「月读」扩展使用。

## 安装

把 `adarkroom.koplugin` 整个目录复制到 KOReader 的 `plugins/` 下，重启 KOReader：

- 独立使用：主菜单「工具 → 小黑屋」。
- 月读扩展：装了月读时，月读会扫描本插件的 `moon_source.lua`（`api = 1`，`id = ext.adarkroom`，`provides = { source = false, home_widgets = {...} }`），在首页编辑「添加组件」里出现「小黑屋」入口。

## 结构

```
adarkroom.koplugin/
  _meta.lua / main.lua          KOReader 插件入口（主菜单）
  moon_source.lua               月读扩展描述（首页入口组件）
  adarkroom/game.lua            宿主入口外观 Game.new(host):show()
  adarkroom/engine.lua          引擎：定时器、合并存盘、模块切换、渲染、Perks
  adarkroom/state.lua           状态树（原版 $SM）、收入、存档迁移
  adarkroom/events.lua          事件框架（随机调度、场景、按钮花费/奖励、延迟事件）
  adarkroom/events/global.lua   全局事件（小偷）
  adarkroom/notifications.lua   通知日志与按模块排队
  adarkroom/l10n.lua            本地化，l10n/zh_cn.lua 由 tools/gen_l10n.py 从上游生成
  adarkroom/room.lua            小黑屋：火与温度（建造者等见第 3 批）
  adarkroom/host/interface.lua  宿主接口：界面 / 定时 / 存档 / 设置 / 提示
  adarkroom/host/koreader.lua   KOReader 适配（settings/adarkroom.lua 存档）
  adarkroom/host/moon.lua       月读适配（存档放 settings/ext.adarkroom.lua）
  adarkroom/ui/screen.lua       通用文本 + 按钮界面
```

游戏代码只依赖 host 接口，不直接碰宿主 API。

## 分批计划

1. **骨架**（已完成）：插件骨架、宿主抽象层、月读入口、最小可玩“生火”界面、许可证。
2. **引擎**（已完成）：Engine / StateManager（`$SM` 等价物）、存档读写与版本迁移、事件系统（events.js 框架）、通知日志、收入定时器。
3. **小黑屋与村庄**：Room（火、温度、陌生人、建造者）、Outside（采集、陷阱、村民分工、人口）、建筑与制作、交易站。
4. **世界地图与战斗**：Path（装备、背包）、World（地图生成、移动、水与食物、地标）、战斗与遭遇事件、Setpieces。
5. **飞船与结局**：Ship、Space（躲避小行星小游戏，用电子墨水友好的回合化方式重做）、Prestige / 计分、中文本地化完善、月读集成打磨。

## 许可证

MPL-2.0，见 `LICENSE`。原作 © doublespeakgames，本项目为移植作品，修改后的源文件同样以 MPL-2.0 发布。

## 测试

无需 KOReader 的冒烟测试：在仓库根目录运行 `lua spec/headless.lua`（Lua 5.1 / LuaJIT / 5.4）。
